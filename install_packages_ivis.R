if (isFALSE(exists("packages")) {
  packages <- c()
}
packages <- c(packages,
              "exactextractr",
              "gganimate",
              "gifski",
              "lubridate",
              "magick",
              "github::ilyamaclean/mesoclim",
              "github::jrmosedale/mesoclimAddTrees",
              "sf",
              "terra",
              "tidyr")
