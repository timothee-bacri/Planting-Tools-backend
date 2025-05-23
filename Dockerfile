FROM r-base:latest

WORKDIR /Planting-Tools

LABEL org.opencontainers.image.source=https://github.com/timothee-bacri/Planting-Tools-backend

ARG CONDA_PATH=/shared/miniconda

# Set dgpsi path version, BUILD ARG
# curl -sSL https://raw.githubusercontent.com/mingdeyu/dgpsi-R/refs/heads/master/R/initi_py.R | grep "env_name *<-" | grep --invert-match "^\s*#" | grep --only-matching --perl-regexp 'dgp.*\d'
ARG DGPSI_FOLDER_NAME

ARG CONDA_ENV_PATH=${CONDA_PATH}/envs/${DGPSI_FOLDER_NAME}
ARG DEBIAN_FRONTEND=noninteractive

# Package installation is split to avoid dependency issues
RUN apt-get update
RUN apt-get -y --no-install-recommends install \
    libcurl4-openssl-dev
# For devtools, dgpsi
RUN apt-get -y --no-install-recommends install \
    libfontconfig1-dev libxml2-dev
RUN apt-get -y --no-install-recommends install \
    libudunits2-dev libssl-dev
RUN apt-get -y --no-install-recommends install \
    libproj-dev cmake
RUN apt-get -y --no-install-recommends install \
    libgdal-dev
RUN apt-get -y --no-install-recommends install \
    libharfbuzz-dev
RUN apt-get -y --no-install-recommends install \
    libfribidi-dev
# Specific to arm64
RUN apt-get -y --no-install-recommends install \
    libgit2-dev
# For RRembo, it depends on eaf
RUN apt-get -y --no-install-recommends install \
    libgsl-dev libglu1-mesa
# For dgpsi
RUN apt-get -y --no-install-recommends install \
    libtiff-dev libjpeg-dev git
# needed to install dgpsi via devtools for some reason
RUN apt-get -y --no-install-recommends install \
    libtool automake
# For gifsky
RUN apt-get -y --no-install-recommends install \
    cargo xz-utils
# For convenience
RUN apt-get -y --no-install-recommends install \
    nano man-db curl cron finger bind9-dnsutils
# For backend (plumber package)
RUN apt-get -y --no-install-recommends install \
    libsodium-dev
# For magick (downscaling)
RUN apt-get -y --no-install-recommends install \
    libmagick++-dev gsfonts
# For rgl (dependency)
RUN apt-get -y --no-install-recommends install \
    libgl1-mesa-dev libglu1-mesa-dev
# For elliptic (dependency)
RUN apt-get -y --no-install-recommends install \
    pari-gp
# For sf, terra
RUN apt-get -y --no-install-recommends install \
    gdal-bin
# For keyring (dependency)
RUN apt-get -y --no-install-recommends install \
    libsecret-1-dev
# For knitr, markdown
RUN apt-get -y --no-install-recommends install \
    pandoc
# Generate SSH key for usage with git
RUN apt-get -y --no-install-recommends install \
    openssh-client

RUN apt-get -y upgrade && \
    apt-get -y clean && \
    apt-get -y autoremove --purge && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Miniconda https://docs.anaconda.com/miniconda/
RUN mkdir -p "${CONDA_PATH}"
RUN arch=$(uname -m) && wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh" -O "${CONDA_PATH}/miniconda.sh"
RUN bash "${CONDA_PATH}/miniconda.sh" -b -u -p "${CONDA_PATH}"
RUN rm -f "${CONDA_PATH}/miniconda.sh"

COPY DESCRIPTION_* .
# Packages update once in a while. We (arbitrarily) update them by invalidating the cache monthly by updating DESCRIPTION
RUN date +%Y-%m && \
    Rscript -e "install.packages('pak')" && \
    # Rscript -e "pak::pkg_install('github::mingdeyu/dgpsi-R')" && \
    for description_file in DESCRIPTION_*; do \
        echo "NOW WORKING WITH THE DESCRIPTION FILE WITH NAME $description_file" && \
        cp $description_file DESCRIPTION && \
        Rscript -e "pak::local_install_dev_deps(upgrade = TRUE)"; \
        rm -f DESCRIPTION; \
    done && \
    rm -rf /tmp/*

# Make conda command available to all
ARG PATH_DOLLAR='$PATH' # do not interpolate $PATH, this is meant to update path in .bashrc
ARG COMMAND_EXPORT_PATH_BASHRC="export PATH=\"${CONDA_PATH}/bin:${PATH_DOLLAR}\""
# $COMMAND_EXPORT_PATH_BASHRC contains: export PATH="<conda_path>/bin:$PATH"
RUN for userpath in /home/*/ /root/; do \
        echo "${COMMAND_EXPORT_PATH_BASHRC}" | tee -a "${userpath}/.bashrc"; \
    done

# Tell all R sessions about it (see details in reticulate:::find_conda())
RUN echo "options(reticulate.conda_binary = '${CONDA_PATH}/bin/conda')" | tee -a "$R_HOME/etc/Rprofile.site"
ENV RETICULATE_CONDA="${CONDA_PATH}/bin/conda"

# Initialize dgpsi, and say yes to all prompts
RUN Rscript -e "readline<-function(prompt) {return('Y')};dgpsi::init_py()"

# Downscaling uses all the magick disk cache -> increase it
# https://stackoverflow.com/questions/31407010/cache-resources-exhausted-imagemagick
RUN sed -E -i 's|  <policy domain="resource" name="disk" value="[0-9]GiB"/>|  <policy domain="resource" name="disk" value="8GiB"/>|' /etc/ImageMagick-*/policy.xml
RUN grep '  <policy domain="resource" name="disk" value=' /etc/ImageMagick-*/policy.xml

ENV API_PORT=40000

HEALTHCHECK --interval=5m --timeout=3s --start-period=10s \
  CMD curl -f http://localhost:${API_PORT}/health || exit 1

# Run plumber in Exec form (https://docs.docker.com/reference/build-checks/json-args-recommended/)
COPY --chmod=755 <<EOT /cmd.bash
#!/usr/bin/env bash
if [ -f /Planting-Tools/ShinyForestry/backend/trigger_plumber_for_dev.R ]; then \
  Rscript /Planting-Tools/ShinyForestry/backend/trigger_plumber_for_dev.R; \
else \
  echo "/Planting-Tools/ShinyForestry/backend/trigger_plumber_for_dev.R not found, doing nothing" && \
  tail -f /dev/null; \
fi
EOT
CMD ["/cmd.bash"]

