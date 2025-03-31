packages <- c("exactextractr",
              "gganimate",
              "gifski",
              "lubridate",
              "github::ilyamaclean/mesoclim",
              "github::jrmosedale/mesoclimAddTrees",
              "sf",
              "terra",
              "tidyr")
available <- sapply(packages, require, character.only = TRUE)
if (length(packages[!available] > 0)) {
  pak::pkg_install(packages[!available],
                   ask = FALSE,
                   upgrade = FALSE)
}
