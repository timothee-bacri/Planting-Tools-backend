packages <- c("exactextractr",
              "gganimate",
              "gifski",
              "lubridate",
              "magick",
              "github::ilyamaclean/mesoclim",
              "github::jrmosedale/mesoclimAddTrees",
              "sf",
              "terra",
              "tidyr")
to_install <- sapply(packages, function(x) {
  return(system.file(package = x) == "")
})
if (any(to_install)) {
  pak::pkg_install(packages[to_install],
                   ask = FALSE,
                   upgrade = FALSE)
}
