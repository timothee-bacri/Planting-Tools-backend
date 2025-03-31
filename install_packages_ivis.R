packages <- c("dplyr",
              "exactextractr",
              "gganimate",
              "gifski",
              "lubridate",
              "github::ilyamaclean/mesoclim",
              "github::jrmosedale/mesoclimAddTrees",
              "sf",
              "terra")
pak::pkg_install(packages,
                 ask = FALSE,
                 upgrade = TRUE)
