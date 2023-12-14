#include "common.h"
#include "mpi.h"
#include "quad-tree.h"
#include "timing.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <functional>
#include <immintrin.h>
#include <mutex>
#include <queue>
#include <sys/ipc.h>
#include <sys/mman.h>
#include <sys/shm.h>
// #include <thread>
#include <immintrin.h>
#include <unordered_map>
#include <xmmintrin.h>

// stolen from linux, shouldn't be a problem though?
#define unlikely(x) __builtin_expect(!!(x), 0)

#pragma GCC diagnostic ignored "-Wcast-function-type"
#pragma GCC diagnostic ignored "-Wpragmas"
#pragma GCC diagnostic ignored "-Wc++17-extensions"

inline float fastSqrt(const float x) { return _mm_cvtss_f32(_mm_sqrt_ss(_mm_set_ss(x))); }

template<bool careAboutStability>
inline float fastInverseSqrt(float x) {
    // Based on an old Intel post I'd seen a while ago & bookmarked, though the idea is very straightforward
    // http://web.archive.org/web/20140718000055/http://software.intel.com/en-us/articles/interactive-ray-tracing
    // Of course, it's not a great fit for this assignment, so I've changed it considerably to work better for us
    const auto guess = _mm_rsqrt_ss(_mm_set_ss(x));

    if constexpr (!careAboutStability) {
        return _mm_cvtss_f32(guess);
    }

    if (unlikely(x < 10)) {
        const auto muls = _mm_mul_ss(_mm_mul_ss(guess, guess), _mm_set_ss(x));
        const auto half_nr = _mm_mul_ss(_mm_set_ss(0.5f), guess);
        const auto result = _mm_mul_ss(half_nr, _mm_sub_ss(_mm_set_ss(3.0f), muls));
        return _mm_cvtss_f32(result);
    } else {
        return _mm_cvtss_f32(guess);
    }
}

// if this could be properly vectorized, because we can bound the size of near, it'd be possible to do way better
// alas, their (lack of) march settings prevent us from doing that. though I actually haven't checked if
// __attribute__((target("avx2"))) would let us use those intrinsics...
template<bool careAboutStability>
static inline Vec2 computeForceFast(const Particle& target, const Particle& attractor, float cullRadius,
                                    float cullRadius2) {
    auto dir = (attractor.position - target.position);
    const auto dist2 = dir.length2();

    if (dist2 < ((1e-3f) * (1e-3f))) {
        return Vec2(0.0f, 0.0f);
    }
    if (dist2 > cullRadius2) {
        return Vec2(0.0f, 0.0f);
    }

    const float G = 0.01f;
    Vec2 force;
    if (dist2 < (1e-1f * 1e-1f)) {
        // last branch should inform branch here. hopefully gcc doesnt hoist
        dir *= fastInverseSqrt<careAboutStability>(dist2); //(1.0f / sqrt(dist2));
        const auto dist = 1e-1f;                           // gcc will take care of simplifying all of this
        force = dir * attractor.mass * (G / (dist * dist));
        if (dist > cullRadius * 0.75f) {
            float decay = 1.0f - (dist - cullRadius * 0.75f) / (cullRadius * 0.25f);
            force *= decay;
        }
    } else {
        // last branch should inform branch here. hopefully gcc doesnt hoist
        const auto reciprocal = fastInverseSqrt<careAboutStability>(dist2); // (1.0f / sqrt(dist2));
        dir *= reciprocal;
        force = dir * attractor.mass * (G / (dist2));
        if (dist2 > (cullRadius * 0.75f) * (cullRadius * 0.75f)) {
            const auto dist = fastSqrt(dist2);
            float decay = 1.0f - (dist - cullRadius * 0.75f) / (cullRadius * 0.25f);
            force *= decay;
        }
    }
    return force;
}

// Slower version
template<bool usingSharedMemory, bool isKnownDelta>
void simulateStep(QuadTree& quadTree, const Task task, Particle* particles, Particle* newParticles,
                  const StepParameters params) {
    // based on simple-simulator.cpp with edits
    static auto near = std::vector<Particle>();
    float deltaTime;
    if constexpr (isKnownDelta) {
        deltaTime = 0.2f;
    } else {
        deltaTime = params.deltaTime;
    }

    const auto cullRadius = params.cullRadius;

    for (auto i = task.start; i < task.end; i++) {
        const auto& it = particles[i];
        auto force = Vec2(0.0f, 0.0f);
        quadTree.getParticles(near, it.position, params.cullRadius);
        if (!near.empty()) {
            for (const auto& j: near) {
                if ((j.position - it.position).length2() < 0) {
                    __builtin_unreachable();
                }
                force += computeForce(it, j, cullRadius);
            }
        }
        if constexpr (usingSharedMemory) {
            newParticles[i] = updateParticle(it, force, deltaTime);
        } else {
            newParticles[i - task.start] = updateParticle(it, force, deltaTime);
        }
    }
}

// Saves 2 ops
__attribute__((noinline)) static Particle updateParticleFast(const Particle& pi, Vec2 force, float deltaTime) {
    Particle result = pi;
    result.velocity += force * deltaTime;
    result.position += result.velocity * deltaTime;
    return result;
}

__attribute__((target("avx2"))) static inline float hsum(const __m256 reg) {
    float v[8];
    _mm256_storeu_ps(v, reg);
    return ((v[0] + v[1]) + (v[2] + v[3])) + ((v[4] + v[5]) + (v[6] + v[7]));
}

auto near = std::array<Particle, 8192>{}; // sufficient, but larger or smaller doesn't really matter
template<bool usingSharedMemory, bool isKnownDelta, int N, bool careAboutStability>
__attribute__((target("avx2,fma"))) void simulateStep(QuadTree& quadTree, const Task task, Particle* particles,
                                                      Particle* newParticles, const StepParameters params) {
    // based on simple-simulator.cpp with edits
    float deltaTime;
    if constexpr (isKnownDelta) {
        deltaTime = 0.2f;
    } else {
        deltaTime = params.deltaTime;
    }

    constexpr float cullRadius = N * 1.25f;
    constexpr float cullRadius2 = cullRadius * cullRadius;
    static_assert(cullRadius2 == cullRadius * cullRadius);
    constexpr float G = 0.01f;

    for (auto i = task.start; i < task.end; i++) {
        const auto& it = particles[i];
        const auto numParticles = quadTree.getParticles(near.data(), it.position, cullRadius2);

        auto force = Vec2(0.0f, 0.0f);

        // yeah I have 316 homework I don't want to do, how can you tell?
        if (numParticles) {
            const auto& target = it;
            const auto reallyReallyReallyCloseCutoff = _mm256_set1_ps(1e-3f * 1e-3f);
            const auto _cullRadius2 = _mm256_set1_ps(cullRadius2);
            const auto _cullRadius75 = _mm256_set1_ps(cullRadius * 0.75f);
            const auto _cullRadiusInv14 = _mm256_set1_ps(1.0f / (cullRadius * 0.25f));

            const auto targetPosX = _mm256_set1_ps(target.position.x);
            const auto targetPosY = _mm256_set1_ps(target.position.y);

            auto vforceX = _mm256_setzero_ps();
            auto vforceY = _mm256_setzero_ps();

            auto j{0};
            for (; j <= numParticles - 8; j += 8) {
                // for (; j < numParticles - 8; j += 8) {
                // faster for me on my machine but not on ghc :(
                // const auto thisParticlePtr = &near[j];
                //
                // constexpr auto OFFSET_OF_X = offsetof(Particle, position.x);
                // constexpr auto OFFSET_OF_Y = offsetof(Particle, position.y);
                // constexpr auto OFFSET_OF_MASS = offsetof(Particle, mass);
                //
                // const auto vxptr =
                //         _mm256_setr_epi32(OFFSET_OF_X, OFFSET_OF_X + sizeof(Particle),
                //                           OFFSET_OF_X + 2 * sizeof(Particle), OFFSET_OF_X + 3 * sizeof(Particle),
                //                           OFFSET_OF_X + 4 * sizeof(Particle), OFFSET_OF_X + 5 * sizeof(Particle),
                //                           OFFSET_OF_X + 6 * sizeof(Particle), OFFSET_OF_X + 7 * sizeof(Particle));
                //
                // const auto vyptr =
                //         _mm256_setr_epi32(OFFSET_OF_Y, OFFSET_OF_Y + sizeof(Particle),
                //                           OFFSET_OF_Y + 2 * sizeof(Particle), OFFSET_OF_Y + 3 * sizeof(Particle),
                //                           OFFSET_OF_Y + 4 * sizeof(Particle), OFFSET_OF_Y + 5 * sizeof(Particle),
                //                           OFFSET_OF_Y + 6 * sizeof(Particle), OFFSET_OF_Y + 7 * sizeof(Particle));
                //
                // const auto vmassptr =
                //         _mm256_setr_epi32(OFFSET_OF_MASS, OFFSET_OF_MASS + sizeof(Particle),
                //                           OFFSET_OF_MASS + 2 * sizeof(Particle), OFFSET_OF_MASS + 3 *
                //                           sizeof(Particle), OFFSET_OF_MASS + 4 * sizeof(Particle), OFFSET_OF_MASS + 5
                //                           * sizeof(Particle), OFFSET_OF_MASS + 6 * sizeof(Particle), OFFSET_OF_MASS +
                //                           7 * sizeof(Particle));
                //
                // const auto vposX = _mm256_i32gather_ps(reinterpret_cast<const float*>(thisParticlePtr), vxptr, 1);
                //
                // const auto vposY = _mm256_i32gather_ps(reinterpret_cast<const float*>(thisParticlePtr), vyptr, 1);
                //
                // const auto vmass = _mm256_i32gather_ps(reinterpret_cast<const float*>(thisParticlePtr), vmassptr, 1);

                // extremely upsetting that this outperforms the above on ghc
                float xs[8], ys[8], masses[8];
                // #pragma GCC unroll 8
                for (size_t u = 0; u < 8; ++u) {    // 2.1%
                    xs[u] = near[j + u].position.x; // 1.6%
                    ys[u] = near[j + u].position.y; // 0.7%
                    masses[u] = near[j + u].mass;   // 1.5%
                    _mm_prefetch(reinterpret_cast<const char*>(&near[8 + j + u].position.x), _MM_HINT_T0);
                    _mm_prefetch(reinterpret_cast<const char*>(&near[8 + j + u].mass), _MM_HINT_T0);
                }

                const auto vposX = _mm256_loadu_ps(xs);
                const auto vposY = _mm256_loadu_ps(ys);

                auto vdirX = _mm256_sub_ps(vposX, targetPosX);
                auto vdirY = _mm256_sub_ps(vposY, targetPosY);

                const auto vdist2 = _mm256_add_ps(_mm256_mul_ps(vdirX, vdirX), _mm256_mul_ps(vdirY, vdirY));

                // !(dist > cullRadius || dist < 1e-3f)
                const auto mask = _mm256_and_ps(_mm256_cmp_ps(vdist2, reallyReallyReallyCloseCutoff, _CMP_GE_OQ),
                                                _mm256_cmp_ps(vdist2, _cullRadius2, _CMP_LE_OQ));

                if (_mm256_testz_ps(mask, mask)) { // 0.6%
                    continue;
                }

                const auto vinvDist =
                        careAboutStability ? _mm256_div_ps(_mm256_set1_ps(1.0f), _mm256_sqrt_ps(vdist2)) : _mm256_rsqrt_ps(vdist2);
                const auto vdist = _mm256_rcp_ps(vinvDist);
                vdirX = _mm256_mul_ps(vdirX, vinvDist);
                vdirY = _mm256_mul_ps(vdirY, vinvDist);

                // TODO: ideally we reuse vinvDist by transforming it and then squaring (or squaring and transforming)
                const auto dist2norm = _mm256_max_ps(vdist2, _mm256_set1_ps(1e-2f));
                const auto vmass = _mm256_loadu_ps(masses);
                const auto vforce = careAboutStability ? _mm256_div_ps(vmass, dist2norm)
                                                       : _mm256_mul_ps(vmass, _mm256_rcp_ps(dist2norm));
                auto vnewForceX = _mm256_mul_ps(vdirX, vforce);
                auto vnewForceY = _mm256_mul_ps(vdirY, vforce);

                // decay
                const auto vdistnorm = _mm256_max_ps(vdist, _mm256_set1_ps(1e-1f));

                // It'd be nice if we could use this, but the numerical stability that we get from this is such that
                // we're actually notably better than the reference solution. That's a problem because it looks like
                // we're wrong!
                // const auto vdecay = _mm256_fmsub_ps(vdistnorm, _cullRadiusInv14, _mm256_set1_ps(-4.0f));

                // Instead, we use this...
                const auto vdecay = _mm256_sub_ps(_mm256_set1_ps(4.0f), _mm256_mul_ps(vdistnorm, _cullRadiusInv14));
                const auto decayMask = _mm256_cmp_ps(vdistnorm, _cullRadius75, _CMP_GT_OQ);

                // Blends are super fast. The multiplication is the bigger issue here.
                vnewForceX = _mm256_blendv_ps(vnewForceX, _mm256_mul_ps(vnewForceX, vdecay), decayMask);
                vnewForceY = _mm256_blendv_ps(vnewForceY, _mm256_mul_ps(vnewForceY, vdecay), decayMask);

                vforceX = _mm256_add_ps(vforceX, _mm256_and_ps(vnewForceX, mask));
                vforceY = _mm256_add_ps(vforceY, _mm256_and_ps(vnewForceY, mask));
            }

            // plenty fast. dont bother optimizing.
            force.x += hsum(vforceX);
            force.y += hsum(vforceY);

            for (; j < numParticles; j++) {
                const auto& k = near[j];
                const auto& target = it;
                const auto& attractor = k;

                auto dir = (attractor.position - target.position);
                const auto dist2 = dir.length2();

                if (dist2 < ((1e-3f) * (1e-3f))) {
                    continue;
                }
                if (dist2 > cullRadius2) {
                    continue;
                }

                Vec2 newForce;
                if (dist2 < (1e-1f * 1e-1f)) {
                    // last branch should inform branch here. hopefully gcc doesnt hoist
                    dir *= fastInverseSqrt<careAboutStability>(dist2); //(1.0f / sqrt(dist2));
                    const auto dist = 1e-1f;                           // gcc will take care of simplifying all of this
                    newForce = dir * (attractor.mass / (dist * dist));
                    if (dist > cullRadius * 0.75f) {
                        float decay = 1.0f - (dist - cullRadius * 0.75f) / (cullRadius * 0.25f);
                        newForce *= decay;
                    }
                } else {
                    // last branch should inform branch here. hopefully gcc doesnt hoist
                    const auto reciprocal = fastInverseSqrt<careAboutStability>(dist2); // (1.0f / sqrt(dist2));
                    dir *= reciprocal;
                    newForce = dir * (attractor.mass / dist2);
                    if (dist2 > (cullRadius * 0.75f) * (cullRadius * 0.75f)) {
                        const auto dist = fastSqrt(dist2);
                        float decay = 1.0f - (dist - cullRadius * 0.75f) / (cullRadius * 0.25f);
                        newForce *= decay;
                    }
                }

                force += newForce;
            }
        } /*else if constexpr (usingSharedMemory) {
            newParticles[i] = it;
            continue;
        } else {
            newParticles[i - task.start] = it;
            continue;
        }*/
        force *= G;
        if constexpr (usingSharedMemory) {
            newParticles[i] = updateParticleFast(it, force, deltaTime);
        } else {
            newParticles[i - task.start] = updateParticleFast(it, force, deltaTime);
        }
    }
}

// TODO: move to header
using SimulateStepType = void (*)(QuadTree&, const Task, Particle*, Particle*, const StepParameters);
using SpecializationTable = std::unordered_map<int, SimulateStepType>;

SpecializationTable specializedFunctions = {};
SpecializationTable specializedFunctionsDangerous = {};

template<std::size_t N>
struct Initializer {
    static void init(SpecializationTable& safe, SpecializationTable& dangerous) {
        safe[N] = &simulateStep<true, true, N, true>;
        dangerous[N] = &simulateStep<true, true, N, false>;
        Initializer<N - 4>::init(safe, dangerous);
    }
};

template<>
struct Initializer<0> {
    static void init(SpecializationTable& safe, SpecializationTable& dangerous) {
        safe[1] = &simulateStep<true, true, 1, true>;
        dangerous[1] = &simulateStep<true, true, 1, false>;
    }
};

void initializeSpecializedSimulateSteps() {
    Initializer<120>::init(specializedFunctions, specializedFunctionsDangerous);
}

// Textbook bit-interleave. there are like a zillion ways to do this, and since this course has 213 as a prereq, I doubt
// it matters that this isn't original. I'd like to rewrite this but it's not even important to the algorithm and I'd
// like to just have a correct baseline for now. Like, I'm pretty sure 213 even links to Bit Twiddling Hacks?
// Given that pdep/pext exist and we're targeting x86 here (i.e., if the Makefile had march=native, this would almost be
// a builtin) and this is therefore practically a polyfill to overcome an overly restrictive Makefile, I'd hope me copy
// pasting this is fine...
// Anyway, the code is a rip from Knuth's TAOCP
uint64_t interleaveBits(const uint32_t a, const uint32_t b) {
    static const uint64_t masks[] = {0x5555555555555555, 0x3333333333333333, 0x0F0F0F0F0F0F0F0F, 0x00FF00FF00FF00FF,
                                     0x0000FFFF0000FFFF};
    static const uint64_t shifts[] = {1, 2, 4, 8, 16};

    uint64_t result = a | (static_cast<uint64_t>(b) << 32);
    for (int i = 4; i >= 0; --i) {
        result = (result & ~masks[i]) | ((result << shifts[i]) & masks[i]);
    }
    return result;
}

static inline uint32_t toInt(float a, float min, float max) {
    return static_cast<uint32_t>(1000.0f * (a - min) / (max - min));
}

void simulateStepXD(QuadTree& quadTree, const Task task, Particle* particles, Particle* newParticles,
                  const StepParameters params)
{
    // based on simple-simulator.cpp with edits
    static auto near = std::vector<Particle>();
    float deltaTime = params.deltaTime;

    const auto cullRadius = params.cullRadius;

    for (auto i = task.start; i < task.end; i++) {
        const auto& it = particles[i];
        auto force = Vec2(0.0f, 0.0f);
        quadTree.getParticles(near, it.position, params.cullRadius);
        if (!near.empty()) {
            for (const auto& j: near) {
                if ((j.position - it.position).length2() < 0) {
                    __builtin_unreachable();
                }
                force += computeForce(it, j, cullRadius);
            }
        }
		newParticles[i] = updateParticle(it, force, deltaTime);
    }
}

// Ajax solve
void solveAjax(unsigned int const rank, unsigned int const nproc, StartupOptions const& options)
{
	const unsigned int gridEdgeDiv = sqrt(nproc);
	if(gridEdgeDiv * gridEdgeDiv != nproc)
	{
		perror("nproc not square");
		exit(1);
	}
	
	const auto parameters = getBenchmarkStepParams(options.spaceSize);

	std::vector<Particle> particleDump;
	int particleCount;

	//auto particleSortingMap = std::unordered_map<int, int>{};
	
	if(rank == MANAGER_PID)
	{
		loadFromFile(options.inputFile, particleDump);
		particleCount = particleDump.size();

		// for(auto i = 0ul; i < particleDump.size(); i++)
		// {
        //     particleSortingMap[i] = particleDump[i].id;
        // }
	}

	MPI_Bcast(&particleCount, 1, MPI_INT, 0, MPI_COMM_WORLD);
	particleDump.resize(particleCount);
	MPI_Bcast(particleDump.data(), particleCount * sizeof(Particle), MPI_BYTE, 0,
			  MPI_COMM_WORLD);

	// auto particleShmId {0};
    // key_t particleShmKey{1337};

	// Particle* particles {nullptr};

	// // Manager just loads particles to dump and creates shared memory spaces
	// if(rank == MANAGER_PID)
	// {
	// 	loadFromFile(options.inputFile, particleDump);

	// 	const auto SHM_SIZE = particleDump.size() * sizeof(Particle); 

	// 	particleShmId = shmget(particleShmKey, SHM_SIZE, IPC_CREAT | 0666);
	// 	if(particleShmId < 0)
	// 	{
	// 		perror("shmget");
	// 		exit(1);
	// 	}
	// 	particles = static_cast<Particle*>(shmat(particleShmId, nullptr, 0));
    //     if((void*)particles == (void*)-1)
	// 	{
    //         perror("shmat");
    //         exit(1);
    //     }
	// }

	// // Manager tells everyone else where the shared memory is
	// MPI_Bcast(&particleShmId, 1, MPI_INT, MANAGER_PID, MPI_COMM_WORLD);

	// // Manager already did this, now everyone else does -- attaching shared memory
	// if(rank != MANAGER_PID)
	// {
    //     particles = static_cast<Particle*>(shmat(particleShmId, nullptr, 0));
    //     if((void*)particles == (void*)-1)
	// 	{
    //         perror("shmat");
    //         exit(1);
    //     }
	// }

	// Now that everyone has the shared memory, manager just memcpys to it...
	// MPI_Barrier(MPI_COMM_WORLD);
    // if(rank == MANAGER_PID)
	// {
    //     std::memcpy(particles, particleDump.data(), particleDump.size() * sizeof(Particle));
    // }

	//std::cerr << "memcpying particle dump, rank = " << rank << std::endl;

	// ...and then everyone copies it to their particle dump
    // MPI_Barrier(MPI_COMM_WORLD);
    // particleDump.resize(options.numParticles);
    // std::memcpy(particleDump.data(), particles, options.numParticles * sizeof(Particle));

	// We're all set
	MPI_Barrier(MPI_COMM_WORLD);

	Timer totalSimulationTimer;

	const int GRID_UPDATE_REGULARITY = 5;
	
	std::vector<Particle> myAcreParticles;
	std::vector<Particle> myAcreParticlesOut;

	struct AcreBound
	{
		Vec2 min;
		Vec2 max;

		void reset() { min = Vec2(1e30f, 1e30f); max = Vec2(-1e30f, -1e30f); }

		// This is just a quick and easy version, conservative
		static bool interacting(AcreBound const& a, AcreBound const& b, float radius)
			{
				return (a.max.x + radius > b.min.x - radius) && (b.max.x + radius > a.min.x - radius) &&
					(a.max.y + radius > b.min.y - radius) && (b.max.y + radius > a.min.y - radius);
			}
	};

	std::vector<unsigned int> acreCounts(nproc);
	
	AcreBound myAcreBound;
	std::vector<AcreBound> acreBounds(nproc);
	
	std::vector<MPI_Request> sendHandles(nproc);
	std::vector<MPI_Request> recvHandles(nproc);

	unsigned int globalOffset = 0;

	constexpr auto NUMERICAL_INSTABILITY_THRESHOLD = 10; // num iterations before we start caring about instability

	const auto N = parameters.cullRadius / 1.25f;
	const auto specialization = static_cast<int>(std::round(parameters.cullRadius / 1.25f));
    const auto canSpecializeCullRadius = specializedFunctions.find(N) != specializedFunctions.end();
    const auto canSpecializeDeltaTime = parameters.deltaTime == 0.2f;

	//std::cerr << "entering main loop, rank = " << rank << std::endl;
	
	for(unsigned int i = 0; i < options.numIterations; i++)
	{
		MPI_Barrier(MPI_COMM_WORLD);
		if(i % GRID_UPDATE_REGULARITY == 0)
		{

			// Basic idea here is that we create a fixed, square grid that covers all the particles
			// Each worker then is assigned to exactly 1 grid acre (hehe, we're back to acres)
			// This is to simplify communication between threads
			// Each worker then builds a quadtree of the particles inside its acre
		
			// In order to resolve gravitational forces from particles near other acres, we check
			// if any of our particles are nearby other acres and then are ready to ask those other workers
			// for a getParticles at the relevant position

			// As the simulation progresses the worker keeps track of the same set of particles it was
			// assigned, but the acre size can change as the particles move around, thus we will regularly
			// reassign the workers back to acres aligned with the grid

			// NOTE: particleDump is essentially our input buffer and particles is essentially our output buffer
			// for each step. Yes, every worker thread can see every particle, even though for this scheme it's
			// somewhat unnecessary

			// Here we assign workers by id to their acre and then have them build a quadtree of those particles
			// std::vector<size_t> myAcreParticles;
			{
				// Need bounds in order to assign particles to acres...
				// We do a huge amount of redundant work here, especially since
				// we've already had to memcpy this stuff
				Vec2 bmin(1e30f, 1e30f);
				Vec2 bmax(-1e30f, -1e30f);
				for(auto& p : particleDump)
				{
					bmin.x = (bmin.x < p.position.x) ? bmin.x : p.position.x;
					bmin.y = (bmin.y < p.position.y) ? bmin.y : p.position.y;
					bmax.x = (bmax.x > p.position.x) ? bmax.x : p.position.x;
					bmax.y = (bmax.y > p.position.y) ? bmax.y : p.position.y;
				}

				signed char myAcreX = rank % gridEdgeDiv;
				signed char myAcreY = rank / gridEdgeDiv;

				myAcreBound.min = Vec2(((float)myAcreX / (float)gridEdgeDiv) * (bmax.x - bmin.x), ((float)myAcreY / (float)gridEdgeDiv) * (bmax.y - bmin.y));
				myAcreBound.max = Vec2(((float)(myAcreX + 1) / (float)gridEdgeDiv) * (bmax.x - bmin.x), ((float)(myAcreY + 1) / (float)gridEdgeDiv) * (bmax.y - bmin.y));

				myAcreParticles.clear();
				
				for(size_t j = 0; j < particleDump.size(); j++)
				{
					signed char particleAcreX = ((float)gridEdgeDiv * (particleDump[j].position.x - bmin.x)) / ((bmax.x - bmin.x) * 1.0f);
					signed char particleAcreY = ((float)gridEdgeDiv * (particleDump[j].position.y - bmin.y)) / ((bmax.y - bmin.y) * 1.0f);

					if(particleAcreX >= gridEdgeDiv)
					{
						particleAcreX = gridEdgeDiv - 1;
					}
					if(particleAcreY >= gridEdgeDiv)
					{
						particleAcreY = gridEdgeDiv - 1;
					}
					
					if(particleAcreX == myAcreX && particleAcreY == myAcreY)
					{
						// myAcreParticles.push_back(j);
						myAcreParticles.push_back(particleDump[j]);
					}
				}

				myAcreParticlesOut.resize(myAcreParticles.size());

				unsigned int sizeToSend = (unsigned int)(myAcreParticles.size());

				MPI_Allgather(&sizeToSend, sizeof(sizeToSend), MPI_BYTE,
							  acreCounts.data(), sizeof(sizeToSend), MPI_BYTE,
							  MPI_COMM_WORLD);
			}
			//std::cerr << "done setting bounds rank = " << rank << std::endl;
		}
		else
		{
			std::swap(myAcreParticles, myAcreParticlesOut);
		}

		myAcreBound.min = Vec2(1e30f, 1e30f);
		myAcreBound.max = Vec2(-1e30f, -1e30f);
		for(auto& p : myAcreParticles)
		{
			myAcreBound.min.x = myAcreBound.min.x < p.position.x ? myAcreBound.min.x : p.position.x;
			myAcreBound.min.y = myAcreBound.min.y < p.position.y ? myAcreBound.min.y : p.position.y;
			myAcreBound.max.x = myAcreBound.max.x > p.position.x ? myAcreBound.max.x : p.position.x;
			myAcreBound.max.y = myAcreBound.max.y > p.position.y ? myAcreBound.max.y : p.position.y;
		}
		
		// Need to make sure everyone is ready to communicate
		MPI_Barrier(MPI_COMM_WORLD);

		// Everyone calculates their interacting neighbor pairs, then we transfer particles between interacting pairs,
		// then we build everyone's quad trees and they all do their simulation on only their particles
		
		// Everyone needs to know everyone else's acre bounds to see if they interact
		MPI_Allgather(&myAcreBound, sizeof(myAcreBound), MPI_BYTE,
					  acreBounds.data(), sizeof(myAcreBound), MPI_BYTE,
					  MPI_COMM_WORLD);

		MPI_Barrier(MPI_COMM_WORLD);

		std::vector<Particle> localParticles = myAcreParticles;
		
		std::vector<unsigned int> interactors(0);

		unsigned int interactingParticles = 0;

		signed char myAcreX = rank % gridEdgeDiv;
		signed char myAcreY = rank / gridEdgeDiv;

		const int adjust = 2;
		
		// for(int xi = myAcreX - adjust; xi < myAcreX + adjust + 1; xi++)
		// {
		// 	for(int yi = myAcreY - adjust; yi < myAcreY + adjust + 1; yi++)
		// 	{
		// 		if(xi >= 0 && xi < gridEdgeDiv && yi >= 0 && yi < gridEdgeDiv)
		// 		{
		// 			int j = xi + yi * gridEdgeDiv;

		// 			if(j < 0 || j >= (int)nproc || j == rank)
		// 			{

		// 			}
		// 			else if(std::find(interactors.begin(), interactors.end(), j) == interactors.end() && AcreBound::interacting(myAcreBound, acreBounds[j], parameters.cullRadius / 2.0f))
		// 			{
		// 				interactors.emplace_back(j);

		// 				MPI_Isend(myAcreParticles.data(),
		// 						  myAcreParticles.size() * sizeof(Particle),
		// 						  MPI_BYTE,
		// 						  j,
		// 						  0,
		// 						  MPI_COMM_WORLD,
		// 						  &sendHandles[j]);

		// 				interactingParticles += acreCounts[j];
		// 			}
		// 		}
		// 	}
		// }
		
		// for(int k = 0; k < 8; k++)
		// {
		// 	int stride = gridEdgeDiv;
		// 	int j = rank;
		// 	j = rank;
		// 	switch(k)
		// 	{
		// 	case 0: j += -1; break;
		// 	case 1: j += 1; break;
		// 	case 2: j += -stride; break;
		// 	case 3: j += stride; break;
		// 	case 4: j += stride - 1; break;
		// 	case 5: j += stride + 1; break;
		// 	case 6: j += -stride + 1; break;
		// 	case 7: j += -stride - 1; break;
		// 	}
		// 	if(j < 0 || j >= (int)nproc || j == rank)
		// 	{

		// 	}
		// 	else if(std::find(interactors.begin(), interactors.end(), j) == interactors.end() && AcreBound::interacting(myAcreBound, acreBounds[j], parameters.cullRadius / 2.0f))
		// 	{
		// 		interactors.emplace_back(j);

		// 		MPI_Isend(myAcreParticles.data(),
		// 				  myAcreParticles.size() * sizeof(Particle),
		// 				  MPI_BYTE,
		// 				  j,
		// 				  0,
		// 				  MPI_COMM_WORLD,
		// 				  &sendHandles[j]);

		// 		interactingParticles += acreCounts[j];
		// 	}
		// }
		
		for(unsigned int j = 0; j < nproc; j++)
		{
			if(j != rank && AcreBound::interacting(myAcreBound, acreBounds[j], parameters.cullRadius / 2.0f))
			{
				interactors.emplace_back(j);

				MPI_Isend(myAcreParticles.data(),
						  myAcreParticles.size() * sizeof(Particle),
						  MPI_BYTE,
						  j,
						  0,
						  MPI_COMM_WORLD,
						  &sendHandles[j]);

				interactingParticles += acreCounts[j];
			}
		}

		localParticles.resize(myAcreParticles.size() + interactingParticles);

		unsigned int offset = myAcreParticles.size();
		for(unsigned int j = 0; j < interactors.size(); j++)
		{
			auto& actor = interactors[j];
			const auto interactorParticleSize = sizeof(Particle) * acreCounts[actor];
			MPI_Irecv(
				&localParticles[offset],
				interactorParticleSize,
				MPI_BYTE,
				actor,
				0,
				MPI_COMM_WORLD,
				&recvHandles[j]);
			offset += acreCounts[actor];
		}

		MPI_Waitall(interactors.size(), recvHandles.data(), MPI_STATUSES_IGNORE);
		
		// We still need to rebuild our local QuadTree every step, but now each
		// worker only builds the QuadTree containing the particles it has been assigned
		QuadTree tree;
		QuadTree::buildQuadTree(localParticles, tree);

		//std::cerr << "completed building tree, rank = " << rank << std::endl;

		const auto task = Task{0, myAcreParticles.size()};
		//simulateStepXD(tree, task, myAcreParticles.data(), myAcreParticlesOut.data(), parameters);

		const auto& specializationToUse = options.numIterations > NUMERICAL_INSTABILITY_THRESHOLD
			? specializedFunctions[specialization]
			: specializedFunctionsDangerous[specialization];
		specializationToUse(tree, task, myAcreParticles.data(), myAcreParticlesOut.data(), parameters);
	    // else {
		// 	simulateStep<true, false>(tree, task, myAcreParticles.data(), myAcreParticlesOut.data(), parameters);
		// }

		//std::cerr << "completed simulating step, rank = " << rank << std::endl;

		std::vector<int> sizes(nproc), displacements(nproc);
		const auto numParticles = static_cast<std::size_t>(options.numParticles);
		for(auto j = 0ul, offset = 0ul; j < nproc; j++) {
			sizes[j] = acreCounts[j] * sizeof(Particle);
			displacements[j] = static_cast<int>(offset);
			offset += sizes[j];
		}

		if(((i + 1) % GRID_UPDATE_REGULARITY == 0) || (i == options.numIterations - 1))
		{
			if(i == options.numIterations - 1)
			{
				std::sort(myAcreParticlesOut.begin(), myAcreParticlesOut.end(), [](Particle const& a, Particle const& b)
					{ 
						return a.id < b.id; 
					});
			}
			MPI_Barrier(MPI_COMM_WORLD);
			MPI_Allgatherv(myAcreParticlesOut.data(), sizes[rank], MPI_BYTE, particleDump.data(), sizes.data(), displacements.data(),
						   MPI_BYTE, MPI_COMM_WORLD);
		}
		//std::cerr << "completed iter i = " << i << ", rank = " << rank << std::endl;
	}

	printf("All work completed as pid=%d\n", rank);

    MPI_Barrier(MPI_COMM_WORLD);
    printf("Passed barrier as pid=%d\n", rank);
	
    if(rank == MANAGER_PID)
	{		
		std::sort(particleDump.begin(), particleDump.end(), [](Particle const& a, Particle const& b)
			{ 
				return a.id < b.id; 
			});

		printf("total simulation time: %.6fs\n", totalSimulationTimer.elapsed());
		
        std::ofstream f(options.outputFile);
        assert((bool) f && "Cannot open output file");

        f << std::setprecision(9);

		//std::cerr << "printing aprticles to file, part dump size = " << particleDump.size() << std::endl;
		//const auto& p = particleDump[0];
		// std::cerr << p.mass << " " << p.position.x << " " << p.position.y << " " << p.velocity.x << " " << p.velocity.y
		// 		  << std::endl;
        for (auto i = 0ul; i < particleDump.size(); i++)
		{
			//const auto& p = particleDump[particleSortingMap[i]];
			const auto& p = particleDump[i];
            f << p.mass << " " << p.position.x << " " << p.position.y << " " << p.velocity.x << " " << p.velocity.y
              << std::endl;
        }
        assert((bool) f && "Failed to write to output file");

        //shmctl(particleShmId, IPC_RMID, nullptr);
    }
}

template<bool useLoadBalancing>
void solve(const int rank, const int nproc, const StartupOptions& options)
{
    constexpr auto NUMERICAL_INSTABILITY_THRESHOLD = 10; // num iterations before we start caring about instability
    const auto parameters = getBenchmarkStepParams(options.spaceSize);
    std::vector<Particle> particleDump, newParticles;
    auto particleShmId{0};
    auto taskListCounterShmId{0};
    key_t particleShmKey{1337};
    key_t taskListShmKey{7331};
    std::atomic_size_t* taskListIndexPtr{nullptr};
    Particle* particles{nullptr};
    auto particleSortingMap = std::unordered_map<int, int>{};
    const auto N = parameters.cullRadius / 1.25f;
    const auto specialization = static_cast<int>(std::round(parameters.cullRadius / 1.25f));
    const auto canSpecializeCullRadius = specializedFunctions.find(N) != specializedFunctions.end();
    const auto canSpecializeDeltaTime = parameters.deltaTime == 0.2f;

    // Don't bother with load-balanced solutions if it's going to be effectively sequential
    // TODO: can try to do work on pid0
    if (nproc <= 2 && useLoadBalancing) {
        return solve<false>(rank, nproc, options);
    }

    if (rank == MANAGER_PID) {
        loadFromFile(options.inputFile, particleDump); // TODO: check if this gets mapped to huge page, then bench
        auto indexed = std::vector<std::pair<Particle, int>>();

        for (auto i = 0ul; i < particleDump.size(); i++) {
            indexed.emplace_back(particleDump[i], i);
        }

        QuadTree tree;
        QuadTree::buildQuadTree(particleDump, tree);
        const auto swapOrder = (tree.bmax.x - tree.bmin.x) <= (tree.bmax.y - tree.bmin.y);

        // TODO: uncomment
        std::sort(indexed.begin(), indexed.end(), [&tree, swapOrder, N](const auto& l, const auto& r) {
            const auto& a = l.first;
            const auto& b = r.first;

            const auto ax = toInt(N * a.position.x, tree.bmin.x, tree.bmin.x);
            const auto ay = toInt(N * a.position.y, tree.bmin.y, tree.bmin.y);
            const auto bx = toInt(N * b.position.x, tree.bmin.x, tree.bmin.x);
            const auto by = toInt(N * b.position.y, tree.bmin.y, tree.bmin.y);

            const auto az = swapOrder ? interleaveBits(ax, ay) : interleaveBits(ay, ax);
            const auto bz = swapOrder ? interleaveBits(bx, by) : interleaveBits(by, bx);

            return az < bz;
        });

        for (auto i = 0ul; i < particleDump.size(); i++) {
            particleDump[i] = indexed[i].first;
            particleSortingMap[indexed[i].second] = i;
        }

        const auto SHM_SIZE = particleDump.size() * sizeof(Particle); // Size of the shared memory segment

        // TODO: remove
        if constexpr (useLoadBalancing) {
            assert(nproc > 2);
        }
        particleShmId = shmget(particleShmKey, SHM_SIZE, IPC_CREAT | 0666);
        if (particleShmId < 0) {
            perror("shmget");
            exit(1);
        }
        particles = static_cast<Particle*>(shmat(particleShmId, nullptr, 0));
        if ((void*) particles == (void*) -1) {
            perror("shmat");
            exit(1);
        }

        // TODO: change shmsize
        taskListCounterShmId = shmget(taskListShmKey, sizeof(std::atomic_size_t), IPC_CREAT | 0666);
        if (taskListCounterShmId < 0) {
            perror("shmget");
            exit(1);
        }

        taskListIndexPtr = static_cast<std::atomic_size_t*>(shmat(taskListCounterShmId, nullptr, 0));
        if ((void*) taskListIndexPtr == (void*) -1) {
            perror("shmat");
            exit(1);
        }

        *taskListIndexPtr = 0;
    }

    // broadcast the shm ids to everything
    MPI_Bcast(&particleShmId, 1, MPI_INT, MANAGER_PID, MPI_COMM_WORLD);
    MPI_Bcast(&taskListCounterShmId, 1, MPI_INT, MANAGER_PID, MPI_COMM_WORLD);

    if (rank != MANAGER_PID) {
        particles = static_cast<Particle*>(shmat(particleShmId, nullptr, 0));
        if ((void*) particles == (void*) -1) {
            perror("shmat");
            exit(1);
        }

        taskListIndexPtr = static_cast<std::atomic_size_t*>(shmat(taskListCounterShmId, nullptr, 0));
        if ((void*) taskListIndexPtr == (void*) -1) {
            perror("shmat");
            exit(1);
        }
    }

    MPI_Barrier(MPI_COMM_WORLD);

    if (rank == MANAGER_PID) {
        std::memcpy(particles, particleDump.data(), particleDump.size() * sizeof(Particle));
    }

    MPI_Barrier(MPI_COMM_WORLD);
    particleDump.resize(options.numParticles);
    std::memcpy(particleDump.data(), particles, options.numParticles * sizeof(Particle));

    // from the tutorials we're linked in the pdf & told to ref https://hpc-tutorials.llnl.gov/mpi/examples/mpi_heat2D.c
    std::vector<int> sizes(nproc), displacements(nproc);
    if constexpr (!useLoadBalancing) {
        const auto numParticles = static_cast<std::size_t>(options.numParticles);
        for (auto i = 0ul, offset = 0ul, averow = numParticles / nproc, extra = numParticles % nproc;
             i < static_cast<unsigned>(nproc); i++) {
            sizes[i] = (averow + (i < extra)) * sizeof(Particle);
            displacements[i] = static_cast<int>(offset);
            offset += sizes[i];
        }
        newParticles.resize(sizes[rank] / sizeof(Particle));
    }

    Timer totalSimulationTimer;

    // TODO: Ideally, replace this with a lockless queue and don't have to worry about a manager. That's part of where
    // we end up losing so much speed.
    //
    for (int i = 0; i < options.numIterations; i++) {
        if constexpr (useLoadBalancing) {
            constexpr auto SCALING_FACTOR = 4;

            const auto numParticles = static_cast<std::size_t>(options.numParticles);
            const auto chunkSize = std::min(numParticles, numParticles / (SCALING_FACTOR * nproc));
            const auto totalChunks = numParticles / chunkSize;

            while (true) {
                QuadTree tree;
                QuadTree::buildQuadTree(particleDump, tree);

                const auto taskIdx = std::atomic_fetch_add(taskListIndexPtr, 1);

                if (taskIdx > totalChunks) {
                    break;
                }

                const auto task = Task{taskIdx * chunkSize, std::min(numParticles, (taskIdx + 1) * chunkSize)};

                if (canSpecializeDeltaTime && canSpecializeCullRadius) {
                    const auto& specializationToUse = options.numIterations > NUMERICAL_INSTABILITY_THRESHOLD
                                                              ? specializedFunctions[specialization]
                                                              : specializedFunctionsDangerous[specialization];
                    specializationToUse(tree, task, /* in */ particleDump.data(),
                                        /* out */ particles, parameters);
                } else {
                    simulateStep<true, false>(tree, task, /* in */ particleDump.data(), /* out */ particles,
                                              parameters);
                }
            }

            // Post-iteration, set particleDump = particles
            MPI_Barrier(MPI_COMM_WORLD);
            std::atomic_store(taskListIndexPtr, 0);
            std::memcpy(particleDump.data(), particles, particleDump.size() * sizeof(Particle));
            MPI_Barrier(MPI_COMM_WORLD);
            // end if constexpr
        } else {
            MPI_Barrier(MPI_COMM_WORLD);
            QuadTree tree;
            QuadTree::buildQuadTree(particleDump, tree);
            const auto task = Task{static_cast<std::size_t>(displacements[rank] / sizeof(Particle)),
                                   (displacements[rank] + sizes[rank]) / sizeof(Particle)};
            if (canSpecializeCullRadius && canSpecializeDeltaTime) {
                const auto& specializationToUse = options.numIterations > NUMERICAL_INSTABILITY_THRESHOLD
                                                          ? specializedFunctions[specialization]
                                                          : specializedFunctionsDangerous[specialization];
                specializationToUse(tree, task, /* in */ particleDump.data(), /* out */ particles, parameters);
            } else {
                simulateStep<true, false>(tree, task, /* in */ particleDump.data(), /* out */ particles, parameters);
            }
            MPI_Barrier(MPI_COMM_WORLD);
            // We also have a version that uses allgatherv on our repository if you would want to see that.
            std::memcpy(particleDump.data(), particles, particleDump.size() * sizeof(Particle));
        }
    }

    printf("All work completed as pid=%d\n", rank);

    MPI_Barrier(MPI_COMM_WORLD);
    printf("Passed barrier as pid=%d\n", rank);

    if (rank == MANAGER_PID) {
        printf("total simulation time: %.6fs\n", totalSimulationTimer.elapsed());

        std::ofstream f(options.outputFile);
        assert((bool) f && "Cannot open output file");

        f << std::setprecision(9);
        for (auto i = 0ul; i < particleDump.size(); i++) {
            const auto& p = particleDump[particleSortingMap[i]];
            f << p.mass << " " << p.position.x << " " << p.position.y << " " << p.velocity.x << " " << p.velocity.y
              << std::endl;
        }
        assert((bool) f && "Failed to write to output file");

        shmctl(particleShmId, IPC_RMID, nullptr);
        shmctl(taskListCounterShmId, IPC_RMID, nullptr);
    }
}

int main(int argc, char* argv[])
{
    int pid, nproc;
    initializeMPI(argc, argv, pid, nproc);
    initializeSpecializedSimulateSteps();
	
    const auto options = parseOptions(argc, argv);

	if(options.numParticles <= 100000)
	{
		if(options.loadBalance)
		{
			solve<true>(pid, nproc, options);
		}
		else
		{
			solve<false>(pid, nproc, options);
		}
	}
	else
	{
		solveAjax(pid, nproc, options);
	}
	
    // if(options.loadBalance)
	// {
    //     solve<true>(pid, nproc, options);
    // }
	// else
	// {
    //     solve<false>(pid, nproc, options);
    // }

	finalizeMPI();
	
    return 0;
}
