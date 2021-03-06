#ifndef THC_GENERIC_FILE
#define THC_GENERIC_FILE "generic/THCTensorMathMagma.cu"
#else

#if defined(THC_REAL_IS_FLOAT) || defined(THC_REAL_IS_DOUBLE)

#ifdef USE_MAGMA

static void THCTensor_(copyArray1d)(THCState *state, THCTensor *self, real *src, int k)
{
  int64_t size[1] = { k };
  int64_t stride[1] = { 1 };
  THCTensor_(resizeNd)(state, self, 1, size, stride);
  size_t len = k * sizeof(real);
  THCudaCheck(cudaMemcpy(THCStorage_(data)(state, self->storage) + self->storageOffset, src, len, cudaMemcpyHostToDevice));
}

static void THCTensor_(copyArray2d)(THCState *state, THCTensor *self, real *src, int m, int n)
{
  int64_t size[2] = { m, n };
  int64_t stride[2] = { 1, m };
  THCTensor_(resizeNd)(state, self, 2, size, stride);
  size_t len = m * n * sizeof(real);
  THCudaCheck(cudaMemcpy(THCStorage_(data)(state, self->storage) + self->storageOffset, src, len, cudaMemcpyHostToDevice));
}

static void THCTensor_(copyTensor2d)(THCState *state, real *dst, THCTensor *self)
{
  THAssert(self->_dim() == 2);
  size_t len = THCTensor_(nElement)(state, self)*sizeof(real);
  THCTensor *temp = THCTensor_(newTranspose)(state, self, 0, 1);
  THCTensor *selfc = THCTensor_(newContiguous)(state, temp);
  THCudaCheck(cudaMemcpy(dst, THCStorage_(data)(state, selfc->storage) + selfc->storageOffset, len, cudaMemcpyDeviceToHost));
  THCTensor_(free)(state, temp);
  THCTensor_(free)(state, selfc);
}

#endif // USE_MAGMA

static THCTensor* THCTensor_(newColumnMajor)(THCState *state, THCTensor *self, THCTensor *src)
{
  THAssert(src->_dim() == 2);
  if (self == src && self->stride[0] == 1 && self->stride[1] == self->size[0])
  {
    THCTensor_(retain)(state, self);
    return self;
  }

  if (self == src)
    self = THCTensor_(new)(state);
  else
    THCTensor_(retain)(state, self);

  int64_t size[2] = { src->size[0], src->size[1] };
  int64_t stride[2] = { 1, src->size[0] };

  THCTensor_(resizeNd)(state, self, 2, size, stride);
  THCTensor_(copy)(state, self, src);
  return self;
}


THC_API void THCTensor_(gesv)(THCState *state, THCTensor *rb_, THCTensor *ra_, THCTensor *b_, THCTensor *a_)
{
#ifdef USE_MAGMA
  THArgCheck(!a_->is_empty() && a_->dim() == 2, 1, "A should be (non-empty) 2 dimensional");
  THArgCheck(!b_->is_empty() && b_->dim() == 2, 2, "b should be (non-empty) 2 dimensional");
  THArgCheck(a_->size[0] == a_->size[1], 1, "A should be square");
  THArgCheck(b_->size[0] == a_->size[0], 2, "A,b size incompatible");

  int64_t n = a_->size[0];
  int64_t nrhs = b_->size[1];

  THCTensor *a = THCTensor_(newColumnMajor)(state, ra_, a_);
  THCTensor *b = THCTensor_(newColumnMajor)(state, rb_, b_);
  real *a_data = THCTensor_(data)(state, a);
  real *b_data = THCTensor_(data)(state, b);

  int *ipiv = th_magma_malloc_pinned<int>(n);

  int info;
#if defined(THC_REAL_IS_FLOAT)
  magma_sgesv_gpu(n, nrhs, a_data, n, ipiv, b_data, n, &info);
#else
  magma_dgesv_gpu(n, nrhs, a_data, n, ipiv, b_data, n, &info);
#endif

  if (info < 0)
    THError("MAGMA gesv : Argument %d : illegal value", -info);
  else if (info > 0)
    THError("MAGMA gesv : U(%d,%d) is zero, singular U.", info, info);

  magma_free_pinned(ipiv);
  THCTensor_(freeCopyTo)(state, a, ra_);
  THCTensor_(freeCopyTo)(state, b, rb_);
#else
  THError(NoMagma(gesv));
#endif
}

THC_API void THCTensor_(trtrs)(THCState *state, THCTensor *rb_, THCTensor *ra_, THCTensor *b_, THCTensor *a_,
                               const char *uplo, const char *trans, const char *diag)
{
#ifdef USE_MAGMA
  THArgCheck(!a_->is_empty() && a_->dim() == 2, 1, "A should be (non-empty) 2 dimensional");
  THArgCheck(!b_->is_empty() && b_->dim() == 2, 2, "b should be (non-empty) 2 dimensional");
  THArgCheck(a_->size[0] == a_->size[1], 1, "A should be square");
  THArgCheck(b_->size[0] == a_->size[0], 2, "A,b size incompatible");

  magma_side_t sz = MagmaLeft;
  magma_uplo_t ul = uplo[0] == 'U' ?  MagmaUpper : MagmaLower;
  magma_trans_t ts = trans[0] == 'N' ? MagmaNoTrans : MagmaTrans;
  magma_diag_t dg = diag[0] == 'U' ? MagmaUnit : MagmaNonUnit;

  real alpha = 1;

  int64_t n = a_->size[0];
  int64_t nrhs = b_->size[1];

  THCTensor *a = THCTensor_(newColumnMajor)(state, ra_, a_);
  THCTensor *b = THCTensor_(newColumnMajor)(state, rb_, b_);
  real *a_data = THCTensor_(data)(state, a);
  real *b_data = THCTensor_(data)(state, b);

#if defined(THC_REAL_IS_FLOAT)
  magma_strsm(sz, ul, ts, dg, n, nrhs, alpha, a_data, n, b_data, n);
#else
  magma_dtrsm(sz, ul, ts, dg, n, nrhs, alpha, a_data, n, b_data, n);
#endif

  THCTensor_(freeCopyTo)(state, a, ra_);
  THCTensor_(freeCopyTo)(state, b, rb_);
#else
  THError(NoMagma(trtrs));
#endif
}

THC_API void THCTensor_(gels)(THCState *state, THCTensor *rb_, THCTensor *ra_, THCTensor *b_, THCTensor *a_)
{
#ifdef USE_MAGMA
  THArgCheck(!a_->is_empty() && a_->dim() == 2, 1, "A should be (non-empty) 2 dimensional");
  THArgCheck(!b_->is_empty() && b_->dim() == 2, 1, "b should be (non-empty) 2 dimensional");
  THArgCheck(a_->size[0] == b_->size[0], 2, "Expected A and b to have same size "
      "at dim 0, but they have incompatible sizes");
  THArgCheck(a_->size[0] >= a_->size[1], 2, "Expected A with shape (m x n) to have "
      "m >= n. The case for m < n is not implemented yet.");

  THCTensor *a = THCTensor_(newColumnMajor)(state, ra_, a_);
  THCTensor *b = THCTensor_(newColumnMajor)(state, rb_, b_);
  real *a_data = THCTensor_(data)(state, a);
  real *b_data = THCTensor_(data)(state, b);

  int64_t m = a->size[0];
  int64_t n = a->size[1];
  int64_t nrhs = b->size[1];
  real wkopt;

  int info;
#if defined(THC_REAL_IS_FLOAT)
  magma_sgels_gpu(MagmaNoTrans, m, n, nrhs, a_data, m, b_data, m, &wkopt, -1, &info);
#else
  magma_dgels_gpu(MagmaNoTrans, m, n, nrhs, a_data, m, b_data, m, &wkopt, -1, &info);
#endif

  real *hwork = th_magma_malloc_pinned<real>((size_t)wkopt);

#if defined(THC_REAL_IS_FLOAT)
  magma_sgels_gpu(MagmaNoTrans, m, n, nrhs, a_data, m, b_data, m, hwork, (int)wkopt, &info);
#else
  magma_dgels_gpu(MagmaNoTrans, m, n, nrhs, a_data, m, b_data, m, hwork, (int)wkopt, &info);
#endif

  magma_free_pinned(hwork);

  if (info != 0)
    THError("MAGMA gels : Argument %d : illegal value", -info);

  THCTensor_(freeCopyTo)(state, a, ra_);
  THCTensor_(freeCopyTo)(state, b, rb_);
#else
  THError(NoMagma(gels));
#endif
}

THC_API void THCTensor_(syev)(THCState *state, THCTensor *re_, THCTensor *rv_, THCTensor *a, const char *jobzs, const char *uplos)
{
#ifdef USE_MAGMA
  int64_t n = a->size[0];
  int64_t lda = n;

  magma_uplo_t uplo = uplos[0] == 'U' ?  MagmaUpper : MagmaLower;
  magma_vec_t jobz = jobzs[0] == 'N' ? MagmaNoVec : MagmaVec;

  THCTensor *input = THCTensor_(newColumnMajor)(state, rv_, a);
  real *input_data = THCTensor_(data)(state, input);

  // eigen values and workspace
  real *w = th_magma_malloc_pinned<real>(n);
  real *wA = th_magma_malloc_pinned<real>(lda * n);

  // compute optimal size of work array
  int info;
  real lwork;
  int liwork;

#if defined(THC_REAL_IS_FLOAT)
  magma_ssyevd_gpu(jobz, uplo, n, input_data, lda, w, wA, n, &lwork, -1, &liwork, -1, &info);
#else
  magma_dsyevd_gpu(jobz, uplo, n, input_data, lda, w, wA, n, &lwork, -1, &liwork, -1, &info);
#endif

  real *work = th_magma_malloc_pinned<real>((size_t)lwork);
  int *iwork = th_magma_malloc_pinned<int>(liwork);

  // compute eigenvalues and, optionally, eigenvectors
#if defined(THC_REAL_IS_FLOAT)
  magma_ssyevd_gpu(jobz, uplo, n, input_data, lda, w, wA, n, work, (int) lwork, iwork, liwork, &info);
#else
  magma_dsyevd_gpu(jobz, uplo, n, input_data, lda, w, wA, n, work, (int) lwork, iwork, liwork, &info);
#endif

  // copy eigen values from w to re_
  if (info == 0)
    THCTensor_(copyArray1d)(state, re_, w, n);

  magma_free_pinned(iwork);
  magma_free_pinned(work);
  magma_free_pinned(wA);
  magma_free_pinned(w);

  // check error value
  if (info > 0)
    THError("MAGMA syev : Failed to converge. %d off-diagonal elements of an didn't converge to zero", info);
  else if (info < 0)
    THError("MAGMA syev : Argument %d : illegal value", -info);

  THCTensor_(freeCopyTo)(state, input, rv_);
#else
  THError(NoMagma(syev));
#endif
}

THC_API void THCTensor_(geev)(THCState *state, THCTensor *re_, THCTensor *rv_, THCTensor *a_, const char *jobvrs)
{
#ifdef USE_MAGMA
  THArgCheck(!a_->is_empty() && a_->dim() == 2, 3, "A should be (non-empty) 2 dimensional");
  THArgCheck(a_->size[0] == a_->size[1], 3, "A should be square");

  magma_vec_t jobvr = jobvrs[0] == 'N' ? MagmaNoVec : MagmaVec;
  int64_t n = a_->size[0];

  real *a_data = th_magma_malloc_pinned<real>(n * n);
  THCTensor_(copyTensor2d)(state, a_data, a_);

  real *wr = th_magma_malloc_pinned<real>(n);
  real *wi = th_magma_malloc_pinned<real>(n);

  real *vr_data = NULL;
  int64_t ldvr = 1;
  if (jobvr == MagmaVec)
  {
    vr_data = th_magma_malloc_pinned<real>(n * n);
    ldvr = n;
  }

  real wkopt;
  int info;

#if defined(THC_REAL_IS_FLOAT)
  magma_sgeev(MagmaNoVec, jobvr, n, a_data, n, wr, wi, NULL, 1, vr_data, ldvr, &wkopt, -1, &info);
#else
  magma_dgeev(MagmaNoVec, jobvr, n, a_data, n, wr, wi, NULL, 1, vr_data, ldvr, &wkopt, -1, &info);
#endif

  int lwork = (int) wkopt;
  real *work_data = th_magma_malloc_pinned<real>(lwork);

#if defined(THC_REAL_IS_FLOAT)
  magma_sgeev(MagmaNoVec, jobvr, n, a_data, n, wr, wi, NULL, 1, vr_data, ldvr, work_data, lwork, &info);
#else
  magma_dgeev(MagmaNoVec, jobvr, n, a_data, n, wr, wi, NULL, 1, vr_data, ldvr, work_data, lwork, &info);
#endif

  if (info > 0)
    THError("MAGMA geev : Failed to converge. %d off-diagonal elements of an didn't converge to zero", info);
  else if (info < 0)
    THError("MAGMA geev : Argument %d : illegal value", -info);

  {
    THCTensor_(resize2d)(state, re_, 2, n);
    THCTensor *re = THCTensor_(newContiguous)(state, re_);
    THCudaCheck(cudaMemcpy(THCStorage_(data)(state, re->storage) + re->storageOffset, wr, n*sizeof(real), cudaMemcpyHostToDevice));
    THCudaCheck(cudaMemcpy(THCStorage_(data)(state, re->storage) + re->storageOffset + n, wi, n*sizeof(real), cudaMemcpyHostToDevice));
    THCTensor_(freeCopyTo)(state, re, re_);
    THCTensor_(transpose)(state, re_, NULL, 0, 1);
  }

  if (jobvr == MagmaVec)
    THCTensor_(copyArray2d)(state, rv_, vr_data, n, n);

  magma_free_pinned(work_data);
  magma_free_pinned(vr_data);
  magma_free_pinned(wi);
  magma_free_pinned(wr);
  magma_free_pinned(a_data);

#else
  THError(NoMagma(geev));
#endif
}

THC_API void THCTensor_(gesvd)(THCState *state, THCTensor *ru_, THCTensor *rs_, THCTensor *rv_, THCTensor *a, const char *jobu)
{
#ifdef USE_MAGMA
  THCTensor *ra_ = THCTensor_(new)(state);
  THCTensor_(gesvd2)(state, ru_, rs_, rv_,  ra_, a, jobu);
  THCTensor_(free)(state, ra_);
#else
  THError(NoMagma(gesvd));
#endif
}

THC_API void THCTensor_(gesvd2)(THCState *state, THCTensor *ru_, THCTensor *rs_, THCTensor *rv_, THCTensor *ra_, THCTensor *a, const char *jobus)
{
#ifdef USE_MAGMA
  THArgCheck(!a->is_empty() && a->dim() == 2, 2, "A should be non-empty 2 dimensional");

  magma_vec_t jobz = jobus[0] == 'A' ? MagmaAllVec : jobus[0] == 'S' ? MagmaSomeVec : jobus[0] == 'O' ? MagmaOverwriteVec : MagmaNoVec;

  int iunused[1];
  int64_t m = a->size[0];
  int64_t n = a->size[1];
  int64_t k = m < n ? m : n;
  int64_t j = (jobz == MagmaAllVec) ? m : k;
  int64_t jv = (jobz == MagmaAllVec) ? n : k;

  real *a_data = th_magma_malloc_pinned<real>(m * n);
  THCTensor_(copyTensor2d)(state, a_data, a);

  real *rs_data = th_magma_malloc_pinned<real>(k);
  real *ru_data = th_magma_malloc_pinned<real>(m * j);
  real *rv_data = th_magma_malloc_pinned<real>(n * n);

  real wkopt;
  int info;

#if defined(THC_REAL_IS_FLOAT)
  magma_sgesdd(jobz, m, n, a_data, m, rs_data, ru_data, m, rv_data, n, &wkopt, -1, iunused, &info);
#else
  magma_dgesdd(jobz, m, n, a_data, m, rs_data, ru_data, m, rv_data, n, &wkopt, -1, iunused, &info);
#endif

  int lwork = (int) wkopt;
  real *work_data = th_magma_malloc_pinned<real>(lwork);
  int *iwork = th_magma_malloc_pinned<int>(8 * k);

#if defined(THC_REAL_IS_FLOAT)
  magma_sgesdd(jobz, m, n, a_data, m, rs_data, ru_data, m, rv_data, n, work_data, lwork, iwork, &info);
#else
  magma_dgesdd(jobz, m, n, a_data, m, rs_data, ru_data, m, rv_data, n, work_data, lwork, iwork, &info);
#endif

  if (info > 0)
    THError("MAGMA gesdd : the updating process of SBDSDC did not converge (error: %d)", info);
  else if (info < 0)
    THError("MAGMA gesdd : Argument %d : illegal value", -info);

  THCTensor_(copyArray2d)(state, rv_, rv_data, n, n);
  THCTensor_(transpose)(state, rv_, NULL, 0, 1);
  if (jobz != MagmaAllVec)
    THCTensor_(narrow)(state, rv_, rv_, 1, 0, jv);
  THCTensor_(copyArray2d)(state, ru_, ru_data, m, j);
  THCTensor_(copyArray1d)(state, rs_, rs_data, k);
  THCTensor_(copyArray2d)(state, ra_, a_data,  m, n);

  magma_free_pinned(work_data);
  magma_free_pinned(iwork);
  magma_free_pinned(rv_data);
  magma_free_pinned(ru_data);
  magma_free_pinned(rs_data);
  magma_free_pinned(a_data);
#else
  THError(NoMagma(gesvd2));
#endif
}

THC_API void THCTensor_(getri)(THCState *state, THCTensor *ra_, THCTensor *a)
{
  THArgCheck(!a->is_empty() && a->dim() == 2, 2, "A should be non-empty 2 dimensional");
  THArgCheck(a->size[0] == a->size[1], 2, "A should be square");

#ifdef USE_MAGMA
  int info;
  int64_t n = a->size[0];
  int lwork = n * magma_get_sgetri_nb(n);

  THCTensor *input = THCTensor_(newColumnMajor)(state, ra_, a);
  real *input_data = THCTensor_(data)(state, input);

  int *ipiv = th_magma_malloc_pinned<int>(n);

  THCTensor *work = THCTensor_(newWithSize1d)(state, lwork);
  real *work_data = THCTensor_(data)(state, work);

  // Run LU
#if defined(THC_REAL_IS_FLOAT)
  magma_sgetrf_gpu(n, n, input_data, n, ipiv, &info);
#else
  magma_dgetrf_gpu(n, n, input_data, n, ipiv, &info);
#endif

  if (info > 0)
    THError("MAGMA getrf : U(%d,%d) is 0, U is singular", info, info);
  else if (info < 0)
    THError("MAGMA getrf : Argument %d : illegal value", -info);

  // Inverse
#if defined(THC_REAL_IS_FLOAT)
  magma_sgetri_gpu(n, input_data, n, ipiv, work_data, lwork, &info);
#else
  magma_dgetri_gpu(n, input_data, n, ipiv, work_data, lwork, &info);
#endif

  if (info > 0)
    THError("MAGMA getri : U(%d,%d) is 0, U is singular", info, info);
  else if (info < 0)
    THError("MAGMA getri : Argument %d : illegal value", -info);

  THCTensor_(free)(state, work);
  magma_free_pinned(ipiv);
  THCTensor_(freeCopyTo)(state, input, ra_);
#else
  int64_t n = a->size[0];

  // input
  THCTensor *input = THCTensor_(newColumnMajor)(state, a, a);
  THCTensor_(resizeNd)(state, ra_, 2, input->size, input->stride);

  real *matrices1[1] = { THCTensor_(data)(state, input) };
  real *matrices2[1] = { THCTensor_(data)(state, ra_) };

  // Copy pointers to device.
  auto d_matrices1 = static_cast<real**>(THCudaMalloc(state, sizeof(real*)));
  auto d_matrices2 = static_cast<real**>(THCudaMalloc(state, sizeof(real*)));

  THCudaCheck(cudaMemcpyAsync(d_matrices1, matrices1, sizeof(real*),
                              cudaMemcpyHostToDevice, THCState_getCurrentStream(state)));
  THCudaCheck(cudaMemcpyAsync(d_matrices2, matrices2, sizeof(real*),
                              cudaMemcpyHostToDevice, THCState_getCurrentStream(state)));
  int info;
  auto info_gpu = static_cast<int*>(THCudaMalloc(state, sizeof(int)));

  auto ipiv_gpu = static_cast<int*>(THCudaMalloc(state, n * sizeof(int)));

  // Run LU
#if defined(THC_REAL_IS_FLOAT)
  THCudaBlas_Sgetrf(state, n, d_matrices1, n, ipiv_gpu, info_gpu, 1);
#else
  THCudaBlas_Dgetrf(state, n, d_matrices1, n, ipiv_gpu, info_gpu, 1);
#endif

  THCudaCheck(cudaMemcpy(&info, info_gpu, sizeof(int), cudaMemcpyDeviceToHost));

  if (info > 0)
    THError("CUBLAS getrf : U(%d,%d) is 0, U is singular", info, info);
  else if (info < 0)
    THError("CUBLAS getrf : Argument %d : illegal value", -info);

  // Inverse
#if defined(THC_REAL_IS_FLOAT)
  THCudaBlas_Sgetri(state, n, (const real**)d_matrices1, n, ipiv_gpu, d_matrices2, n, info_gpu, 1);
#else
  THCudaBlas_Dgetri(state, n, (const real**)d_matrices1, n, ipiv_gpu, d_matrices2, n, info_gpu, 1);
#endif

  THCudaCheck(cudaMemcpy(&info, info_gpu, sizeof(int), cudaMemcpyDeviceToHost));

  if (info > 0)
    THError("CUBLAS getri : U(%d,%d) is 0, U is singular", info, info);
  else if (info < 0)
    THError("CUBLAS getri : Argument %d : illegal value", -info);

  THCudaFree(state, ipiv_gpu);
  THCudaFree(state, info_gpu);

  THCudaFree(state, d_matrices1);
  THCudaFree(state, d_matrices2);

  THCTensor_(free)(state, input);
#endif
}

__global__ void THCTensor_(copyUpperSymmetric)(real *input, int n, int len)
{
  for (int idx = threadIdx.x + blockIdx.x * blockDim.x; idx < len; idx += 65535) {
    const int r = idx % n;
    const int c = idx / n;
    if (r > c) {
      input[idx] = input[r*n + c];
    }
  }
}

__global__ void THCTensor_(copyLowerSymmetric)(real *input, int n, int len)
{
  for (int idx = threadIdx.x + blockIdx.x * blockDim.x; idx < len; idx += 65535) {
    const int r = idx % n;
    const int c = idx / n;
    if (r < c) {
      input[idx] = input[r*n + c];
    }
  }
}

THC_API void THCTensor_(potri)(THCState *state, THCTensor *ra_, THCTensor *a, const char *uplo)
{
#ifdef USE_MAGMA
  THArgCheck(!a->is_empty() && a->dim() == 2, 2, "A should be non-empty 2 dimensional");
  THArgCheck(a->size[0] == a->size[1], 2, "A should be square");

  int64_t n = a->size[0];
  magma_uplo_t ul = uplo[0] == 'U' ?  MagmaUpper : MagmaLower;

  THCTensor *input = THCTensor_(newColumnMajor)(state, ra_, a);
  real *input_data = THCTensor_(data)(state, input);

  int info;
#if defined(THC_REAL_IS_FLOAT)
  magma_spotri_gpu(ul, n, input_data, n, &info);
#else
  magma_dpotri_gpu(ul, n, input_data, n, &info);
#endif

  if (info > 0)
    THError("MAGMA potri : A(%d,%d) is 0, A cannot be factorized", info, info);
  else if (info < 0)
    THError("MAGMA potri : Argument %d : illegal value", -info);

  cudaStream_t stream = THCState_getCurrentStream(state);
  const int len = n*n;
  dim3 blocks(std::min(DIVUP(len, 128), 65535));
  dim3 threads(128);
  if (uplo[0] == 'U') {
    THCTensor_(copyUpperSymmetric)<<<blocks, threads, 0, stream>>>(input_data, n, len);
  } else {
    THCTensor_(copyLowerSymmetric)<<<blocks, threads, 0, stream>>>(input_data, n, len);
  }

  THCTensor_(freeCopyTo)(state, input, ra_);
#else
  THError(NoMagma(potri));
#endif
}

THC_API void THCTensor_(potrf)(THCState *state, THCTensor *ra_, THCTensor *a, const char *uplo)
{
#ifdef USE_MAGMA
  THArgCheck(!a->is_empty() && a->dim() == 2, 2, "A should be (non-empty) 2 dimensional");
  THArgCheck(a->size[0] == a->size[1], 2, "A should be square");

  int64_t n = a->size[0];
  magma_uplo_t ul = uplo[0] == 'U' ?  MagmaUpper : MagmaLower;

  THCTensor *input = THCTensor_(newColumnMajor)(state, ra_, a);
  real *input_data = THCTensor_(data)(state, input);

  int info;
#if defined(THC_REAL_IS_FLOAT)
  magma_spotrf_gpu(ul, n, input_data, n, &info);
#else
  magma_dpotrf_gpu(ul, n, input_data, n, &info);
#endif

  // check error value
  if (info > 0)
    THError("MAGMA potrf : A(%d,%d) is 0, A cannot be factorized", info, info);
  else if (info < 0)
    THError("MAGMA potrf : Argument %d : illegal value", -info);

  if (uplo[0] == 'U') {
    THCTensor_(triu)(state, ra_, input, 0);
  } else {
    THCTensor_(tril)(state, ra_, input, 0);
  }
  THCTensor_(free)(state, input);
#else
  THError(NoMagma(potrf));
#endif
}

THC_API void THCTensor_(potrs)(THCState *state, THCTensor *rb_, THCTensor *b, THCTensor *a, const char *uplo)
{
#ifdef USE_MAGMA
  THArgCheck(a->size[0] == a->size[1], 2, "A should be square");

  int64_t n = a->size[0];
  int64_t nrhs = b->size[1];
  magma_uplo_t ul = uplo[0] == 'U' ?  MagmaUpper : MagmaLower;

  THCTensor *b_ = THCTensor_(newColumnMajor)(state, rb_, b);
  real *b_data = THCTensor_(data)(state, b_);
  THCTensor *a_ = THCTensor_(newColumnMajor)(state, a, a);
  real *a_data = THCTensor_(data)(state, a_);

  int info;
#if defined(THC_REAL_IS_FLOAT)
  magma_spotrs_gpu(ul, n, nrhs, a_data, n, b_data, n, &info);
#else
  magma_dpotrs_gpu(ul, n, nrhs, a_data, n, b_data, n, &info);
#endif

  // check error value
  if (info < 0)
    THError("MAGMA potrs : Argument %d : illegal value", -info);

  THCTensor_(freeCopyTo)(state, b_, rb_);
  THCTensor_(free)(state, a_);
#else
  THError(NoMagma(potrs));
#endif
}

THC_API void THCTensor_(geqrf)(THCState *state, THCTensor *ra_, THCTensor *rtau_, THCTensor *a_)
{
#ifdef USE_MAGMA
  THArgCheck(!a_->is_empty() && a_->dim() == 2, 2, "A should be non-empty 2 dimensional");

  THCTensor *a = THCTensor_(newColumnMajor)(state, ra_, a_);
  int64_t m = a->size[0];
  int64_t n = a->size[1];
  int64_t k = (m < n ? m : n);

#if defined(THC_REAL_IS_FLOAT)
  int64_t nb = magma_get_sgeqrf_nb(m, n);
#else
  int64_t nb = magma_get_dgeqrf_nb(m, n);
#endif

  real *rtau_data = th_magma_malloc_pinned<real>(k);
  real *a_data = THCTensor_(data)(state, a);

  int info;
#if defined(THC_REAL_IS_FLOAT)
  magma_sgeqrf2_gpu(m, n, a_data, m, rtau_data, &info);
#else
  magma_dgeqrf2_gpu(m, n, a_data, m, rtau_data, &info);
#endif

  if (info != 0)
    THError("MAGMA geqrf2 : Argument %d : illegal value.", -info);

  THCTensor_(freeCopyTo)(state, a, ra_);
  THCTensor_(copyArray1d)(state, rtau_, rtau_data, k);
  magma_free_pinned(rtau_data);
#else
  THError(NoMagma(geqrf));
#endif
}

THC_API void THCTensor_(qr)(THCState *state, THCTensor *rq_, THCTensor *rr_, THCTensor *a_)
{
#ifdef USE_MAGMA
  THArgCheck(!a_->is_empty() && a_->dim() == 2, 2, "A should be non-empty 2 dimensional");

  THCTensor *a = THCTensor_(newColumnMajor)(state, rr_, a_);
  int64_t m = a->size[0];
  int64_t n = a->size[1];
  int64_t k = (m < n ? m : n);

#if defined(THC_REAL_IS_FLOAT)
  int64_t nb = magma_get_sgeqrf_nb(m, n);
#else
  int64_t nb = magma_get_dgeqrf_nb(m, n);
#endif

  real *a_data = THCTensor_(data)(state, a);
  real *tau_data = th_magma_malloc_pinned<real>(k);
  THCTensor *work = THCTensor_(newWithSize1d)(state, (2*k + magma_roundup(n, 32))*nb);
  real *work_data = THCTensor_(data)(state, work);

  int info;
  // We need to call two different versions of ?geqrf:
  //   ?geqrf_gpu allows fast computation of Q via ?orqrf_gpu, but doesn't give
  //     R properly. Note that the MAGMA documentation for this method is wrong.
  //     http://icl.cs.utk.edu/magma/forum/viewtopic.php?f=2&t=1015&p=2800&hilit=geqrf_gpu#p2800
  //   ?geqrf2_gpu gives correct R, but doesn't allow computation of Q via ?orqrf_gpu
#if defined(THC_REAL_IS_FLOAT)
  magma_sgeqrf2_gpu(m, n, a_data, m, tau_data, &info);
#else
  magma_dgeqrf2_gpu(m, n, a_data, m, tau_data, &info);
#endif

  if (info != 0)
    THError("MAGMA geqrf2 : Argument %d : illegal value.", -info);

  THCTensor_(narrow)(state, a, a, 0, 0, k);
  THCTensor_(triu)(state, rr_, a, 0);
  THCTensor_(free)(state, a);

  a = THCTensor_(newColumnMajor)(state, rq_, a_);
  a_data = THCTensor_(data)(state, a);

#if defined(THC_REAL_IS_FLOAT)
  magma_sgeqrf_gpu(m, n, a_data, m, tau_data, work_data, &info);
#else
  magma_dgeqrf_gpu(m, n, a_data, m, tau_data, work_data, &info);
#endif

  if (info != 0)
    THError("MAGMA geqrf : Argument %d : illegal value.", -info);

  THCTensor *q = THCTensor_(newColumnMajor)(state, rq_, a);
  real *q_data = THCTensor_(data)(state, q);

#if defined(THC_REAL_IS_FLOAT)
  magma_sorgqr_gpu(m, k, k, q_data, m, tau_data, work_data, nb, &info);
#else
  magma_dorgqr_gpu(m, k, k, q_data, m, tau_data, work_data, nb, &info);
#endif

  if (info != 0)
    THError("MAGMA orgqr : Argument %d : illegal value.", -info);

  THCTensor_(free)(state, a);
  THCTensor_(free)(state, work);
  magma_free_pinned(tau_data);

  THCTensor_(narrow)(state, q, q, 1, 0, k);
  THCTensor_(freeCopyTo)(state, q, rq_);
#else
  THError(NoMagma(qr));
#endif
}

#endif

#endif
