
#' @export
cleanColumnNames <- function(x) {
  x <- iconv(x, "UTF-8", "ASCII", sub="") # clean odd characters in stationID
  x <- gsub("\\[[^\\]]*\\]|\\:.*$|\\.", "", x, perl=TRUE) # remove text between [...]
  #  \[                       # '['
  #    [^\]]*                 # any character except: '\]' (0 or more
  #                           # times (matching the most amount possible))
  #    \]                     # ']'
  #    \\:.*$                 # remove everything after colon
  #    \\.                    # remove .
  x <- gsub("[ ]+$", "", x)   # now remove trailing space
  x <- gsub("[ ]+", "_", x) # replace spaces with _
  x
}

#' @export
#' @importFrom utils read.table
read.dbexport <- function(fname, sep = "\t", na.strings = "NULL") {
  out <- read.table(fname, sep = sep, header = TRUE, na.strings = na.strings, stringsAsFactors = FALSE)
  clean_names <- strsplit(readLines(fname, n = 1), sep)[[1]]
  names(out) <- cleanColumnNames(clean_names)
  out
}


#' @export

O2satFun <- function(temp) {
  tempabs <- temp + 273.15
  exp(-173.4292 + 249.6339 * (100/tempabs) +
        143.3483 * log(tempabs/100) - 21.8492 * (tempabs/100) +
        (-0.033096 + 0.014259 * (tempabs/100) - 0.0017000 * (tempabs/100)^2)
  ) * 1.428  # * Oxygen saturation in mg/l
}

#' @export
#' @importFrom sp coordinates
#' @importFrom sp CRS
#' @importFrom sp proj4string

makeSpatial <- function(x) {
  sp::coordinates(x) <- ~ x + y
  sp::proj4string(x) <- sp::CRS("+proj=utm +zone=34 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0")
  x
}
