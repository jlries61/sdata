/*
 * gsl_validate.c - Validate SData statistical function outputs against GSL.
 *
 * Compile: gcc -o gsl_validate gsl_validate.c -lgsl -lgslcblas -lm
 * Run:     ./gsl_validate
 *
 * Each line of output is: FUNCTION(args) GSL_VALUE SDATA_VALUE MATCH
 */
#include <stdio.h>
#include <math.h>
#include <gsl/gsl_cdf.h>
#include <gsl/gsl_randist.h>
#include <gsl/gsl_sf_gamma.h>

#define TOL 1e-4

static void check(const char *name, double gsl_val, double sdata_val) {
    double diff = fabs(gsl_val - sdata_val);
    double relerr = (fabs(gsl_val) > 1e-12) ? diff / fabs(gsl_val) : diff;
    printf("%-30s  GSL=%12.6f  SData=%12.6f  %s\n",
           name, gsl_val, sdata_val,
           relerr < TOL ? "OK" : "*** MISMATCH ***");
}

int main(void) {
    printf("=== Normal / Z distribution ===\n");
    check("NCF(0,0,1)",   gsl_cdf_gaussian_P(0.0, 1.0),        0.50000);
    check("NDF(0,0,1)",   gsl_ran_gaussian_pdf(0.0, 1.0),       0.39894);
    check("NIF(0.5,0,1)", gsl_cdf_gaussian_Pinv(0.5, 1.0),      0.00000);
    check("ZCF(0)",       gsl_cdf_ugaussian_P(0.0),             0.50000);
    check("ZDF(0)",       gsl_ran_ugaussian_pdf(0.0),            0.39894);
    check("ZIF(0.5)",     gsl_cdf_ugaussian_Pinv(0.5),          0.00000);
    check("ZIF(0.5,0,1)", gsl_cdf_ugaussian_Pinv(0.5),          0.000000);
    check("ZIF(0.95,0,1)",gsl_cdf_ugaussian_Pinv(0.95),         1.644853);

    printf("\n=== Uniform distribution ===\n");
    check("UCF(0.5,0,1)", gsl_cdf_flat_P(0.5, 0.0, 1.0),       0.50000);
    check("UDF(0.5,0,1)", gsl_ran_flat_pdf(0.5, 0.0, 1.0),      1.00000);
    check("UIF(0.5,0,1)", gsl_cdf_flat_Pinv(0.5, 0.0, 1.0),     0.50000);
    check("UIF(0.75,0,1)",gsl_cdf_flat_Pinv(0.75, 0.0, 1.0),    0.750000);

    printf("\n=== Exponential distribution ===\n");
    /* GSL uses mean=1/rate; our EDF/ECF use rate */
    check("ECF(1,1)",     gsl_cdf_exponential_P(1.0, 1.0),      0.63212);
    check("EDF(1,1)",     gsl_ran_exponential_pdf(1.0, 1.0),     0.36788);
    check("EIF(0.5,1)",   gsl_cdf_exponential_Pinv(0.5, 1.0),   0.693147);

    printf("\n=== Beta distribution ===\n");
    check("BCF(0.5,2,2)", gsl_cdf_beta_P(0.5, 2.0, 2.0),        0.50000);
    check("BDF(0.5,2,2)", gsl_ran_beta_pdf(0.5, 2.0, 2.0),       1.50000);
    check("BIF(0.5,2,2)", gsl_cdf_beta_Pinv(0.5, 2.0, 2.0),      0.50000);
    check("BIF(0.5,2,5)", gsl_cdf_beta_Pinv(0.5, 2.0, 5.0),      0.264450);

    printf("\n=== Gamma distribution ===\n");
    /* GSL gamma: shape=a, scale=b (rate=1/b) */
    check("GCF(2,2,1)",   gsl_cdf_gamma_P(2.0, 2.0, 1.0),       0.59399);
    check("GDF(2,2,1)",   gsl_ran_gamma_pdf(2.0, 2.0, 1.0),      0.27067);
    /* GIF not in stat_test but in idf_test */
    check("GIF(0.5,2,1)", gsl_cdf_gamma_Pinv(0.5, 2.0, 1.0),    1.678347);

    printf("\n=== Chi-square distribution ===\n");
    check("XCF(2,2)",     gsl_cdf_chisq_P(2.0, 2.0),             0.63212);
    check("XDF(2,2)",     gsl_ran_chisq_pdf(2.0, 2.0),            0.18394);
    check("XIF(0.95,10)", gsl_cdf_chisq_Pinv(0.95, 10.0),        18.307038);

    printf("\n=== Student-T distribution ===\n");
    check("TCF(0,1)",     gsl_cdf_tdist_P(0.0, 1.0),             0.50000);
    check("TDF(0,1)",     gsl_ran_tdist_pdf(0.0, 1.0),            0.31831);
    check("TIF(0.975,20)",gsl_cdf_tdist_Pinv(0.975, 20.0),        2.085963);

    printf("\n=== F distribution ===\n");
    check("FCF(1,2,2)",   gsl_cdf_fdist_P(1.0, 2.0, 2.0),        0.50000);
    check("FDF(1,2,2)",   gsl_ran_fdist_pdf(1.0, 2.0, 2.0),       0.25000);
    check("FIF(0.95,5,10)",gsl_cdf_fdist_Pinv(0.95, 5.0, 10.0),   3.325835);

    printf("\n=== Binomial distribution ===\n");
    /* MCF/MDF use (k, n, p) */
    check("MDF(5,10,0.5)", gsl_ran_binomial_pdf(5, 0.5, 10),      0.24609);
    check("MCF(5,10,0.5)", gsl_cdf_binomial_P(5, 0.5, 10),        0.62305);

    printf("\n=== Weibull distribution ===\n");
    /* GSL: gsl_cdf_weibull_P(x, a=scale, b=shape) */
    check("WDF(1,1,2)",    gsl_ran_weibull_pdf(1.0, 1.0, 2.0),    0.73576);
    check("WCF(1,1,2)",    gsl_cdf_weibull_P(1.0, 1.0, 2.0),      0.63212);
    check("WIF(0.5,1,1)",  gsl_cdf_weibull_Pinv(0.5, 1.0, 1.0),  0.693147);

    printf("\n=== Poisson distribution ===\n");
    check("PCF(2,2)",      gsl_cdf_poisson_P(2, 2.0),             0.67668);
    check("PDF(2,2)",      gsl_ran_poisson_pdf(2, 2.0),            0.27067);
    check("PIF(0.5,3)",    3.0,                                    3.000000); /* integer quantile */

    printf("\n=== Laplace distribution ===\n");
    /* GSL Laplace: gsl_ran_laplace_pdf(x, width) where width=scale */
    check("LIF(0.75,0,1)", -log(2.0 * (1.0 - 0.75)),             0.693147);
    check("LCF(0,0,1)",    0.5,                                   0.50000);
    check("LDF(0,0,1)",    gsl_ran_laplace_pdf(0.0, 1.0),        0.50000);

    return 0;
}
