#' Run a script through some protocols such as http, https, ftp, etc.
#'
#' Internally, \code{source_url} calls \code{\link{getURL}} in
#' \code{RCurl} package and then read the contents by
#' \code{\link{textConnection}}, which is then \code{\link{source}}ed
#' or \code{\link[Rcpp]{sourceCpp}}ed.
#' See \code{?getURL} for the available protocol.
#'
#' If a SHA-1 hash is specified with the \code{sha1} argument, then this
#' function will check the SHA-1 hash of the first downloaded file to make sure it
#' matches the expected value, and throw an error if it does not match. If the
#' SHA-1 hash is not specified, it will print a message displaying the hash of
#' the downloaded file. The purpose of this is to improve security when running
#' remotely-hosted code; if you have a hash of the file, you can be sure that
#' it has not changed. For convenience, it is possible to use a truncated SHA1
#' hash, down to 6 characters, but keep in mind that a truncated hash won't be
#' as secure as the full hash.
#'
#' If there are multiple urls, \code{source_url} will download all of them
#' and put them into the same temporal directory with their file name. The
#' first one will be executed accoring to its file extension.
#'
#' @param url url
#' @param ... other options passed to \code{\link{source}}
#' @param sha1 The (prefix of the) SHA-1 hash of the file at the remote URL.
#' @export
#' @examples
#' \dontrun{
#'
#' source_url("https://gist.github.com/hadley/6872663/raw/hi.r")
#'
#' # With a hash, to make sure the remote file hasn't changed
#' source_url("https://gist.github.com/hadley/6872663/raw/hi.r",
#'   sha1 = "54f1db27e60bb7e0486d785604909b49e8fef9f9")
#'
#' # With a truncated hash
#' source_url("https://gist.github.com/hadley/6872663/raw/hi.r",
#'   sha1 = "54f1db27e60")
#' }
source_url <- function(url, ..., sha1 = NULL) {
  stopifnot(is.character(url), length(url) > 0)

  download.root <- tempfile(pattern="source_url_download")
  dir.create(download.root)

  download.target <- character(length(url))
  for(i in seq_along(url)) {
    filename <- names(url[i])
    download.target[i] <- normalizePath(sprintf("%s/%s", download.root, filename), mustWork=FALSE)
    request <- httr::GET(url[i])
    httr::stop_for_status(request)
    writeBin(httr::content(request, type = "raw"), download.target[i])
  }
  file_sha1 <- digest::digest(file = download.target[i], algo = "sha1")

  if (is.null(sha1)) {
    message("SHA-1 hash of the first file is ", file_sha1)
  } else {
    if (nchar(sha1) < 6) {
      stop("Supplied SHA-1 hash is too short (must be at least 6 characters)")
    }

    # Truncate file_sha1 to length of sha1
    file_sha1 <- substr(file_sha1, 1, nchar(sha1))

    if (!identical(file_sha1, sha1)) {
      stop("SHA-1 hash of the first downloaded file (", file_sha1,
        ")\n does not match expected value (", sha1, ")", call. = FALSE)
    }
  }
  message(sprintf("Sourcing the first file: %s", names(url)[1]))
  switch(tools::file_ext(names(url)[1]),
    "r" = source(download.target[1], ...),
    "R" = source(download.target[1], ...),
    "cpp" = Rcpp::sourceCpp(download.target[1], ...),
    "cc" = Rcpp::sourceCpp(download.target[1], ...)
    )
}

#' Run a script on gist
#'
#' \dQuote{Gist is a simple way to share snippets and pastes with others.
#'   All gists are git repositories, so they are automatically versioned,
#'   forkable and usable as a git repository.}
#' \url{https://gist.github.com/}
#'
#' @param id either full url (character), gist ID (numeric or character of
#'   numeric). If a gist ID is specified and the entry has multiple files,
#'   only the first R/cpp file in the gist is \code{\link{source}}ed or \code{\link[Rcpp]{sourceCpp}}ed.
#' @param ... other options passed to \code{\link{source}} or \code{\link[Rcpp]{sourceCpp}}.
#' @param sha1 The SHA-1 hash of the file at the remote URL. This is highly
#'   recommend as it prevents you from accidentally running code that's not
#'   what you expect. See \code{\link{source_url}} for more information on
#'   using a SHA-1 hash.
#' @param quiet if \code{FALSE}, the default, prints informative messages.
#' @export
#' @examples
#' # You can run gists given their id
#' source_gist(6872663)
#' source_gist("6872663")
#'
#' # Or their html url
#' source_gist("https://gist.github.com/hadley/6872663")
#' source_gist("gist.github.com/hadley/6872663")
#'
#' # It's highly recommend that you run source_gist with the optional
#' # sha1 argument - this will throw an error if the file has changed since
#' # you first ran it
#' source_gist(6872663, sha1 = "54f1db27e60")
#' \dontrun{
#' # Wrong hash will result in error
#' source_gist(6872663, sha1 = "54f1db27e61")
#' }
source_gist <- function(id, ..., sha1 = NULL, quiet = FALSE) {
  stopifnot(length(id) == 1)

  url_match <- "((^https://)|^)gist.github.com/([^/]+/)?([0-9a-f]+)$"
  if (grepl(url_match, id)) {
    # https://gist.github.com/kohske/1654919, https://gist.github.com/1654919,
    # or gist.github.com/1654919
    id <- regmatches(id, regexec(url_match, id))[[1]][5]
    url <- find_gist(id)
  } else if (is.numeric(id) || grepl("^[0-9a-f]+$", id)) {
    # 1654919 or "1654919"
    url <- find_gist(id)
  } else {
    stop("Unknown id: ", id)
  }

  if (!quiet) sapply(url, function(u) message("Sourcing ", u))
  source_url(url, ..., sha1 = sha1)
}

find_gist <- function(id) {
  files <- github_GET(sprintf("gists/%s", id))$files
  sapply(files, function(obj) obj$raw_url)
}
