packages <- c("dplyr",
              "exactextractr",
              "gganimate",
              "gifski",
              "lubridate",
              "mesoclim",
              "mesoclimAddTrees",
              "sf",
              "terra")
pak::pkg_install(packages,
                 ask = FALSE,
                 upgrade = TRUE)
