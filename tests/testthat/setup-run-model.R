
## A single set of valid model options and data, update once instead of copying
## for every test.

a_hintr_data <- list(
  pjnz = system_file("extdata/mwi2019.PJNZ"),
  population = system_file("extdata/population/population_agesex.csv"),
  shape = system_file("extdata/areas/area_merged.geojson"),
  survey = system_file("extdata/survey/survey_hiv_indicators.csv"),
  art_number = system_file("extdata/programme/art_number.csv"),
  anc_testing = system_file("extdata/programme/anc_testing.csv")
)

a_hintr_options <- list(
  area_scope = "MWI_1_2",
  area_level = "4",
  calendar_quarter_t1 = "CY2016Q1",
  calendar_quarter_t2 = "CY2018Q3",
  calendar_quarter_t3 = "CY2019Q2",
  survey_prevalence = c("MWI2016PHIA", "MWI2015DHS"),
  survey_art_coverage = "MWI2016PHIA",
  survey_recently_infected = "MWI2016PHIA",
  include_art_t1 = "true",
  include_art_t2 = "true",
  anc_prevalence_year1 = 2016,
  anc_prevalence_year2 = 2018,
  anc_art_coverage_year1 = 2016,
  anc_art_coverage_year2 = 2018,
  spectrum_population_calibration = "none",
  spectrum_plhiv_calibration_level = "none",
  spectrum_plhiv_calibration_strat = "sex_age_group",
  spectrum_artnum_calibration_level = "none",
  spectrum_artnum_calibration_strat = "age_coarse",
  spectrum_infections_calibration_level = "none",
  spectrum_infections_calibration_strat = "age_coarse",
  artattend = "true",
  artattend_t2 = "false",
  artattend_log_gamma_offset = -4L,
  rng_seed = 17,
  no_of_samples = 20,
  max_iter = 250,
  permissive = "false"
)

a_hintr_output <- hintr_run_model(a_hintr_data, a_hintr_options)

a_hintr_options_bad <- a_hintr_options
a_hintr_options_bad$calendar_quarter_t2 <- NULL

a_hintr_calibration_options <- list(
  spectrum_plhiv_calibration_level = "subnational",
  spectrum_plhiv_calibration_strat = "sex_age_group",
  spectrum_artnum_calibration_level = "none",
  spectrum_artnum_calibration_strat = "age_coarse",
  spectrum_infections_calibration_level = "none",
  spectrum_infections_calibration_strat = "age_coarse"
)

## Use fit.RDS if it exists locally, otherwise just use the actual functions
## fit.RDS not on git because it is pretty massive ~ 220MB
if (file.exists("testdata/fit.RDS")) {
  model_output <- readRDS("testdata/fit.RDS")
  fit <- mockery::mock(model_output, cycle = TRUE)
  sample <- mockery::mock(model_output, cycle = TRUE)
} else {
  fit <- fit_tmb
  sample <- sample_tmb
}

naomi_evaluate_promise <- function (code, print = FALSE) {
  warnings <- testthat:::Stack$new()
  handle_warning <- function(condition) {
    warnings$push(condition)
    invokeRestart("muffleWarning")
  }
  messages <- testthat:::Stack$new()
  handle_message <- function(condition) {
    messages$push(condition)
    invokeRestart("muffleMessage")
  }
  progress <- testthat:::Stack$new()
  handle_progress <- function(condition) {
    progress$push(condition)
    invokeRestart("muffleProgress")
  }
  temp <- file()
  on.exit(close(temp))
  result <- withr::with_output_sink(
    temp,
    withCallingHandlers(withVisible(code),
                        warning = handle_warning,
                        message = handle_message,
                        progress = handle_progress))
  if (result$visible && print) {
    withr::with_output_sink(temp, print(result$value))
  }
  output <- paste0(readLines(temp, encoding = "UTF-8", warn = FALSE),
                   collapse = "\n")
  list(result = result$value,
       output = output,
       warnings = testthat:::get_messages(warnings$as_list()),
       messages = testthat:::get_messages(messages$as_list()),
       progress = progress$as_list())
}

MockProgress <- R6::R6Class(
  "MockProgress",
  inherit = Progress,
  cloneable = FALSE,
  public = list(
    ## Wrap print message in a with restarts so we can capture messages for
    ## testing
    print = function() {
      withRestarts({
        super$print()
      }, muffleProgress = function(...) NULL)
    }
  )
)

clone_output <- function(output) {
  output_path <- tempfile()
  file.copy(output$output_path, output_path)
  spectrum_path <- tempfile(fileext = ".zip")
  file.copy(output$spectrum_path, spectrum_path)
  coarse_output_path <- tempfile(fileext = ".zip")
  file.copy(output$coarse_output_path, coarse_output_path)
  summary_report_path <- tempfile(fileext = ".html")
  file.copy(output$summary_report_path, summary_report_path)
  calibration_path <- tempfile(fileext = ".rds")
  file.copy(output$calibration_path, calibration_path)
  build_hintr_output(output_path, spectrum_path, coarse_output_path,
                     summary_report_path, calibration_path,
                     output$metadata)
}

expect_file_equivalent <- function(path_object, path_expected) {
  object_md5 <- tools::md5sum(path_object)
  expected_md5 <- tools::md5sum(path_expected)
  expect_equal(object_md5, expected_md5, check.attributes = FALSE)
}

expect_file_different <- function(path_object, path_expected) {
  object_md5 <- tools::md5sum(path_object)
  expected_md5 <- tools::md5sum(path_expected)
  expect_false(isTRUE(all.equal(object_md5, expected_md5,
                                check.attributes = FALSE)))
}
