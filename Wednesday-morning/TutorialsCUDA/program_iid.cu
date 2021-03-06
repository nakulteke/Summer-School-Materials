#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>
#include <math.h>

//-----------------------------------------------------------------------------
// GpuConstantsPackage: a struct to hold many constants (including pointers
//                      to allocated memory on the device) that can be
//                      uploaded all at once.  Placing this in the "constants
//                      cache" is a convenient and performant way of handling
//                      constant information on the GPU.
//-----------------------------------------------------------------------------
struct GpuConstantsPackage {
  int     nparticle;
  int*    partType;
  float*  partX;
  float*  partY;
  float*  partZ;
  float*  partQ;
  float*  Etot;
};
typedef struct GpuConstantsPackage cribSheet;

// This device constant is available to all functions in this CUDA unit
__device__ __constant__ cribSheet cSh;

//-----------------------------------------------------------------------------
// GpuMirroredInt: a struct holding mirrored int data on both the CPU and the
//                 GPU.  Functions below will operate on this struct
//                 (because this isn't a workshop on C++)
//-----------------------------------------------------------------------------
struct GpuMirroredInt {
  int len;          // Length of the array (again, this is not a C++ course)
  int IsPinned;     // "Pinned" memory is best for Host <= => GPU transfers.
                    //   In fact, if non-pinned memory is transferred to the
                    //   GPU from the host, a temporary allocation of pinned
                    //   memory will be created and then destroyed.  Pinned
                    //   memory is not host-pageable, but the only performance
                    //   implication is that creating lots of pinned memory
                    //   may make it harder for the host OS to manage large
                    //   memory jobs.
  int* HostData;    // Pointer to allocated memory on the host
  int* DevcData;    // Pointer to allocated memory on the GPU.  Note that the
                    //   host can know what the address of memory on the GPU
                    //   is, but it cannot simply de-reference that pointer
                    //   in host code.
};
typedef struct GpuMirroredInt gpuInt;

//-----------------------------------------------------------------------------
// GpuMirroredInt: a struct holding mirrored fp32 data on both the CPU and the
//                 GPU.  Functions below will operate on this struct
//                 (because this isn't a workshop on C++)
//-----------------------------------------------------------------------------
struct GpuMirroredFloat {
  int len;          // Length of the array (again, this is not a C++ course)
  int IsPinned;     // "Pinned" memory is best for Host <= => GPU transfers.
                    //   In fact, if non-pinned memory is transferred to the
                    //   GPU from the host, a temporary allocation of pinned
                    //   memory will be created and then destroyed.  Pinned
                    //   memory is not host-pageable, but the only performance
                    //   implication is that creating lots of pinned memory
                    //   may make it harder for the host OS to manage large
                    //   memory jobs.
  float* HostData;  // Pointer to allocated memory on the host
  float* DevcData;  // Pointer to allocated memory on the GPU.  Note that the
                    //   host can know what the address of memory on the GPU
                    //   is, but it cannot simply de-reference that pointer
                    //   in host code.
};
typedef struct GpuMirroredFloat gpuFloat;

//-----------------------------------------------------------------------------
// ParticleSimulator: run a rudimentary simulation of particles
//-----------------------------------------------------------------------------
__global__ void ParticleSimulator()
{
  // Loop over all particles and compute the electrostatic potential.
  // Each thread will accumulate its own portion of the potential,
  // then pool the results at the end.
  int tidx = threadIdx.x;
  float qq = 0.0;
  while (tidx < cSh.nparticle) {

    // Still the naive way, to show how slow it is
    int i;
    for (i = 0; i < tidx; i++) {
      float dx = cSh.partX[tidx] - cSh.partX[i];
      float dy = cSh.partY[tidx] - cSh.partY[i];
      float dz = cSh.partZ[tidx] - cSh.partZ[i];
      float r = sqrt(dx*dx + dy*dy + dz*dz);
      qq += cSh.partQ[tidx] * cSh.partQ[i] / r;
    }

    // Increment counter
    tidx += blockDim.x;
  }

  // Accumulate energy
  atomicAdd(&cSh.Etot[0], qq);
}

//-----------------------------------------------------------------------------
// CreateGpuInt: constructor function for allocating memory in a gpuInt
//               instance.
//
// Arguments:
//   len:      the length of array to allocate
//   pin:      flag to have the memory pinned (non-pageable on the host side
//             for optimal transfer speed to the device)
//-----------------------------------------------------------------------------
gpuInt CreateGpuInt(int len, int pin)
{
  gpuInt G;

  G.len = len;
  G.IsPinned = pin;
  
  // Now that the official length is recorded, upgrade the real length
  // to the next convenient multiple of 128, so as to always allocate
  // GPU memory in 512-byte blocks.  This is for alignment purposes,
  // and keeping host to device transfers in line.
  len = ((len + 127) / 128) * 128;
  if (pin == 1) {
    cudaHostAlloc((void **)&G.HostData, len * sizeof(int),
		  cudaHostAllocMapped);
  }
  else {
    G.HostData = (int*)malloc(len * sizeof(int));
  }
  cudaMalloc((void **)&G.DevcData, len * sizeof(int));
  memset(G.HostData, 0, len * sizeof(int));
  cudaMemset((void *)G.DevcData, 0, len * sizeof(int));

  return G;
}

//-----------------------------------------------------------------------------
// DestroyGpuInt: destructor function for freeing memory in a gpuInt
//                instance.
//-----------------------------------------------------------------------------
void DestroyGpuInt(gpuInt *G)
{
  if (G->IsPinned == 1) {
    cudaFreeHost(G->HostData);
  }
  else {
    free(G->HostData);
  }
  cudaFree(G->DevcData);
}

//-----------------------------------------------------------------------------
// UploadGpuInt: upload an integer array from the host to the device.
//-----------------------------------------------------------------------------
void UploadGpuInt(gpuInt *G)
{
  cudaMemcpy(G->DevcData, G->HostData, G->len * sizeof(int),
             cudaMemcpyHostToDevice);
}

//-----------------------------------------------------------------------------
// DownloadGpuInt: download an integer array from the host to the device.
//-----------------------------------------------------------------------------
void DownloadGpuInt(gpuInt *G)
{
  cudaMemcpy(G->HostData, G->DevcData, G->len * sizeof(int),
	     cudaMemcpyHostToDevice);
}

//-----------------------------------------------------------------------------
// CreateGpuFloat: constructor function for allocating memory in a gpuFloat
//                 instance.
//
// Arguments:
//   len:      the length of array to allocate
//   pin:      flag to have the memory pinned (non-pageable on the host side
//             for optimal transfer speed ot the device)
//-----------------------------------------------------------------------------
gpuFloat CreateGpuFloat(int len, int pin)
{
  gpuFloat G;

  G.len = len;
  G.IsPinned = pin;
  
  // Now that the official length is recorded, upgrade the real length
  // to the next convenient multiple of 128, so as to always allocate
  // GPU memory in 512-byte blocks.  This is for alignment purposes,
  // and keeping host to device transfers in line.
  len = ((len + 127) / 128) * 128;
  if (pin == 1) {
    cudaHostAlloc((void **)&G.HostData, len * sizeof(float),
		  cudaHostAllocMapped);
  }
  else {
    G.HostData = (float*)malloc(len * sizeof(float));
  }
  cudaMalloc((void **)&G.DevcData, len * sizeof(float));
  memset(G.HostData, 0, len * sizeof(float));
  cudaMemset((void *)G.DevcData, 0, len * sizeof(float));

  return G;
}

//-----------------------------------------------------------------------------
// DestroyGpuFloat: destructor function for freeing memory in a gpuFloat
//                  instance.
//-----------------------------------------------------------------------------
void DestroyGpuFloat(gpuFloat *G)
{
  if (G->IsPinned == 1) {
    cudaFreeHost(G->HostData);
  }
  else {
    free(G->HostData);
  }
  cudaFree(G->DevcData);
}

//-----------------------------------------------------------------------------
// UploadGpuFloat: upload an float array from the host to the device.
//-----------------------------------------------------------------------------
void UploadGpuFloat(gpuFloat *G)
{
  cudaMemcpy(G->DevcData, G->HostData, G->len * sizeof(float),
             cudaMemcpyHostToDevice);
}

//-----------------------------------------------------------------------------
// DownloadGpuFloat: download an float array from the host to the device.
//-----------------------------------------------------------------------------
void DownloadGpuFloat(gpuFloat *G)
{
  cudaMemcpy(G->HostData, G->DevcData, G->len * sizeof(float),
	     cudaMemcpyHostToDevice);
}

//-----------------------------------------------------------------------------
// main
//-----------------------------------------------------------------------------
int main()
{
  int i, np;
  gpuInt particleTypes;
  gpuFloat particleXcoord, particleYcoord, particleZcoord, particleCharge;
  gpuFloat etot;
  
  // Create a small array of particles and populate it
  particleTypes  = CreateGpuInt(100000, 1);
  particleXcoord = CreateGpuFloat(100000, 1);
  particleYcoord = CreateGpuFloat(100000, 1);
  particleZcoord = CreateGpuFloat(100000, 1);
  particleCharge = CreateGpuFloat(100000, 1);

  // Allocate and initialize the total energy
  // accumulator on the host and on the device.
  etot = CreateGpuFloat(1, 1);
  
  // Initialize random number generator.  srand() SEEDS the generator,
  // thereafter each call to rand() will return a different number.
  // This is a reeally bad generator (much better methods with longer
  // periods before they start looping back over the same sequence are
  // available).
  srand(62052);
  
  // Place many, many particles
  np = 97913;
  for (i = 0; i < np; i++) {

    // Integer truncation would happen anyway, I'm just making it explicit
    particleTypes.HostData[i] = (int)(8 * rand());

    // Create some random coordinates (double-to-float conversion
    // is happening here.  On the GPU this can have performance
    // impact, so keep an eye on the data types at all times!
    particleXcoord.HostData[i] = 200.0 * (double)rand() / (double)RAND_MAX;
    particleYcoord.HostData[i] = 200.0 * (double)rand() / (double)RAND_MAX;
    particleZcoord.HostData[i] = 200.0 * (double)rand() / (double)RAND_MAX;
    particleCharge.HostData[i] =   0.5 - (double)rand() / (double)RAND_MAX;
  }

  // Show the CPU result
#if 0
  int j;
  double qq = 0.0;
  for (i = 0; i < np; i++) {
    for (j = 0; j < i; j++) {
      double dx = particleXcoord.HostData[i] - particleXcoord.HostData[j];
      double dy = particleYcoord.HostData[i] - particleYcoord.HostData[j];
      double dz = particleZcoord.HostData[i] - particleZcoord.HostData[j];
      double qfac = particleCharge.HostData[i] * particleCharge.HostData[j];
      qq += qfac / sqrt(dx*dx + dy*dy + dz*dz);
    }
  }
  printf("CPU result = %9.4lf\n", qq);
#endif
  
  // Stage critical constants--see cribSheet struct instance cSh above.
  cribSheet cnstage;
  cnstage.nparticle = np;
  cnstage.partX = particleXcoord.DevcData;
  cnstage.partY = particleYcoord.DevcData;
  cnstage.partZ = particleZcoord.DevcData;
  cnstage.partQ = particleCharge.DevcData;
  cnstage.Etot  = etot.DevcData; 
  
  // Upload all data to the device
  UploadGpuInt(&particleTypes);
  UploadGpuFloat(&particleXcoord);
  UploadGpuFloat(&particleYcoord);
  UploadGpuFloat(&particleZcoord);
  UploadGpuFloat(&particleCharge);

  // Upload the constants to the constants cache
  cudaMemcpyToSymbol(cSh, &cnstage, sizeof(cribSheet));  
  
  // Launch the kernel with different numbers of threads
  for (i = 1024; i >= 128; i /= 2) {

    // Zero the total energy and upload (this could be done by the GPU in
    // a separate kernel, but it's convenient enough to do it this way)
    etot.HostData[0] = 0.0;
    UploadGpuFloat(&etot);
    ParticleSimulator<<<1, i>>>();
  
    // Download the total energy
    DownloadGpuFloat(&etot);
    printf("Total energy (%4d threads) = %10.4f\n", i, etot.HostData[0]);
  }
  
  // Device synchronization
  cudaDeviceSynchronize();
  
  return 0;
}
