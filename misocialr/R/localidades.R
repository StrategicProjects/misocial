# IBGE state codes (the first two digits of every municipality code).
mds_states <- c(
  RO = 11, AC = 12, AM = 13, RR = 14, PA = 15, AP = 16, TO = 17,
  MA = 21, PI = 22, CE = 23, RN = 24, PB = 25, PE = 26, AL = 27, SE = 28,
  BA = 29, MG = 31, ES = 32, RJ = 33, SP = 35, PR = 41, SC = 42, RS = 43,
  MS = 50, MT = 51, GO = 52, DF = 53
)

# Municipalities whose official 7-digit code does not follow the IBGE
# check-digit rule. Checked against the IBGE localities API
# (servicodados.ibge.gov.br/api/v1/localidades/municipios): the rule matches
# 5,562 of 5,571 codes; these are the 9 exceptions.
ibge_dv_exceptions <- c(
  "220191" = "2201919", "220198" = "2201988", "220225" = "2202251",
  "261153" = "2611533", "311783" = "3117836", "315213" = "3152131",
  "430587" = "4305871", "520393" = "5203939", "520396" = "5203962"
)

#' Convert 6-digit MDS municipality codes to 7-digit IBGE codes
#'
#' The MI Social API identifies municipalities by the first six digits of
#' the IBGE code (without the check digit). This helper restores the
#' official 7-digit code, using the IBGE check-digit rule plus the table of
#' municipalities that are exceptions to it.
#'
#' @param x Character or numeric vector of 6-digit codes.
#'
#' @return A character vector of 7-digit IBGE codes (`NA` for inputs that
#'   are not 6 digits).
#'
#' @examples
#' ibge_code7(c(261160, "260790"))
#'
#' @export
ibge_code7 <- function(x) {
  x <- as.character(x)
  # Computed once per distinct code: long outputs repeat each municipality
  # in every field and month.
  u <- unique(x)
  ok <- !is.na(u) & grepl("^[0-9]{6}$", u)
  out <- rep(NA_character_, length(u))
  out[ok] <- paste0(u[ok], vapply(u[ok], ibge_check_digit, character(1)))
  exc <- ok & u %in% names(ibge_dv_exceptions)
  out[exc] <- unname(ibge_dv_exceptions[u[exc]])
  out[match(x, u)]
}

#' IBGE check digit of a 6-digit municipality code
#'
#' Weights 1,2,1,2,1,2; two-digit products contribute the sum of their
#' digits; the digit completes the total to the next multiple of 10.
#' @noRd
ibge_check_digit <- function(code6) {
  d <- as.integer(strsplit(code6, "")[[1]])
  p <- d * rep_len(c(1L, 2L), 6)
  s <- sum(p %/% 10L + p %% 10L)
  as.character((10L - s %% 10L) %% 10L)
}

#' Normalize one municipality code to the 6 digits used by the API
#' @noRd
normalize_municipality <- function(x) {
  x <- as.character(x)
  if (length(x) != 1 || is.na(x) || !grepl("^[0-9]{6,7}$", x)) {
    abort_mds(c(
      "{.arg locality} must be a single 6- or 7-digit IBGE municipality code.",
      "i" = "Example: {.val 2611606} or {.val 261160} (Recife)."
    ), "validation")
  }
  check_dv(x)
  substr(x, 1, 6)
}

#' Reject 7-digit codes whose check digit is wrong
#'
#' Without this, the last digit would simply be dropped and a typo such as
#' 2611600 would silently query Recife (261160).
#' @noRd
check_dv <- function(x) {
  x7 <- x[nchar(x) == 7]
  bad <- x7[ibge_code7(substr(x7, 1, 6)) != x7]
  if (length(bad) > 0) {
    abort_mds(c(
      "!" = "Wrong check digit in municipality code(s): {.val {bad}}.",
      "i" = "Did you mean {.val {ibge_code7(substr(bad, 1, 6))}}?"
    ), "validation")
  }
  invisible(TRUE)
}

#' List municipalities available in the API
#'
#' Returns the municipalities as identified by the MI Social API, with the
#' 6-digit code the API uses and the official 7-digit IBGE code. The list is
#' read from one month (by default December of the last closed year), paged
#' and checked for completeness; it is cached for the session.
#'
#' @param state Optional state abbreviations (e.g. `"PE"`) or 2-digit IBGE
#'   state codes (e.g. `26`). `NULL` (default) returns all of Brazil.
#' @param period Month (`YYYYMM`) the list is read from. `NULL` (default)
#'   uses December of the last closed year. The territorial division of that
#'   month is what is returned.
#' @param refresh Logical. Ignore the cached list and ask the API again?
#'   Default `FALSE`.
#'
#' @return A tibble with columns `locality_id` (6 digits, as in the API),
#'   `ibge_code` (7 digits), `locality_name`, `state` and `region`. The
#'   month and time of the request are kept in `attr(x, "period")` and
#'   `attr(x, "retrieved_at")`.
#'
#' @examplesIf interactive()
#' mds_localities("PE")
#'
#' @export
mds_localities <- function(state = NULL, period = NULL, refresh = FALSE) {
  check_flag(refresh, "refresh")
  period <- if (is.null(period)) localities_period() else parse_periods(period)
  if (length(period) != 1) {
    abort_mds("{.arg period} must be a single month (YYYYMM).", "validation")
  }
  ufs <- if (!is.null(state)) states_to_abbr(state)

  key <- paste0("localities|", period)
  locs <- cache_get(key, refresh)
  if (is.null(locs)) locs <- cache_set(key, fetch_localities(period))

  if (is.null(ufs)) return(locs)
  out <- locs[locs$state %in% ufs, ]
  attributes(out)[c("period", "retrieved_at")] <-
    attributes(locs)[c("period", "retrieved_at")]
  out
}

#' Read and check the municipality list of one month
#' @noRd
fetch_localities <- function(period) {
  docs <- fetch_all_pages(
    list(
      fq = paste0("anomes_s:", period),
      fl = "id,codigo_ibge,municipio,sigla_uf,regiao",
      sort = "id asc"
    ),
    .label = "localities"
  )
  if (length(docs) == 0) {
    abort_mds(c(
      "The MI Social API has no municipality for {.val {period}}.",
      "i" = "Choose another month with {.arg period}."
    ), "response")
  }
  check_doc_identity(lapply(docs, function(d) {
    d$anomes_s <- period
    d
  }))
  locs <- tibble::tibble(
    locality_id   = doc_chr(docs, "codigo_ibge"),
    locality_name = doc_chr(docs, "municipio"),
    state         = doc_chr(docs, "sigla_uf"),
    region        = doc_chr(docs, "regiao")
  )
  dup <- unique(locs$locality_id[duplicated(locs$locality_id)])
  if (length(dup) > 0) {
    abort_mds(c(
      "The MI Social API listed a municipality twice.",
      "x" = "Repeated code{?s}: {.val {utils::head(dup, 3)}}."
    ), "response")
  }
  locs <- locs |>
    dplyr::mutate(ibge_code = ibge_code7(.data$locality_id),
                  .after = "locality_id") |>
    dplyr::arrange(.data$locality_id)
  attr(locs, "period") <- period
  locs
}

#' Month used to list municipalities
#'
#' Every month carries all municipalities; December of the last closed year
#' is used so that the names reflect the current territorial division.
#' @noRd
localities_period <- function(today = Sys.Date()) {
  paste0(as.integer(format(today, "%Y")) - 1L, "12")
}

#' Convert state codes or abbreviations to abbreviations
#' @noRd
states_to_abbr <- function(state) {
  state <- toupper(as.character(state))
  by_code <- names(mds_states)[match(state, as.character(mds_states))]
  # as.character(): ifelse() on an empty vector returns logical(0).
  out <- as.character(ifelse(state %in% names(mds_states), state, by_code))
  invalid <- state[is.na(out)]
  if (length(invalid) > 0) {
    abort_mds(c(
      "!" = "Unknown state(s): {.val {invalid}}.",
      "i" = "Use abbreviations ({.val PE}) or 2-digit IBGE codes ({.val 26})."
    ), "validation")
  }
  out
}

#' Parse the `localities` argument into Solr filter values
#'
#' Accepts `"BR"` (all of Brazil), state abbreviations or 2-digit codes, and
#' 6- or 7-digit municipality codes, in any combination.
#'
#' @return A list with `states` (abbreviations) and `municipalities`
#'   (6-digit codes); both empty means the whole country.
#' @noRd
parse_localities <- function(localities) {
  x <- toupper(trimws(whole_text(localities)))

  # An empty selection must not fall through to "no filter", which would
  # query the whole country.
  if (length(x) == 0 || anyNA(x) || any(x == "")) {
    abort_mds(c(
      "{.arg localities} must have at least one value and no missing values.",
      "i" = "Use {.val BR}, a state ({.val PE}) or municipality codes."
    ), "validation")
  }

  is_br <- x == "BR"
  is_mun <- !is_br & grepl("^[0-9]{6,7}$", x)
  is_state <- !is_br & !is_mun &
    (x %in% names(mds_states) | grepl("^[0-9]{2}$", x))
  invalid <- x[!is_br & !is_mun & !is_state]

  if (length(invalid) > 0) {
    abort_mds(c(
      "!" = "Invalid locality value(s): {.val {invalid}}.",
      "i" = "Use {.val BR}, state abbreviations ({.val PE}), 2-digit state
             codes ({.val 26}) or 6/7-digit municipality codes
             ({.val 2611606})."
    ), "validation")
  }

  # Every value is validated, even when "BR" makes the others redundant.
  states <- unique(states_to_abbr(x[is_state]))
  check_dv(x[is_mun])

  if (any(is_br)) {
    return(list(states = character(), municipalities = character()))
  }

  list(states = states, municipalities = unique(substr(x[is_mun], 1, 6)))
}
