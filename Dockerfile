FROM rocker/r-ubuntu:latest

WORKDIR /Planting-Tools

LABEL org.opencontainers.image.source=https://github.com/timothee-bacri/Planting-Tools-backend

ARG MINIFORGE_PATH=/shared/miniforge

# Set dgpsi path version as a BUILD ARG
# curl -sSL https://raw.githubusercontent.com/mingdeyu/dgpsi-R/refs/heads/master/R/initi_py.R | \
#            sed --silent '/devel/,$p' | \
#            grep --max-count 1 --only-matching --perl-regexp '^((?!#).)*env_name.*$' | \
#            grep --only-matching "['\"].*['\"]" | \
#            tr --delete "'" | tr --delete '"'
ARG DGPSI_FOLDER_NAME
# ARG CONDA_ENV_PATH=${MINIFORGE_PATH}/envs/${DGPSI_FOLDER_NAME}

ARG DEBIAN_FRONTEND=noninteractive

# Package installation is split to avoid dependency issues
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
    # To download files
    wget \
    libcurl4-openssl-dev \
    # For devtools and dgpsi
    libfontconfig1-dev libxml2-dev libudunits2-dev libssl-dev libproj-dev cmake libgdal-dev libharfbuzz-dev libfribidi-dev \
    # Specific to arm64
    libgit2-dev \
    # For RRembo, it depends on eaf
    libgsl-dev libglu1-mesa \
    # For dgpsi
    libtiff-dev libjpeg-dev git \
    # needed to install dgpsi via devtools for some reason
    libtool automake \
    # For gifsky
    cargo xz-utils \
    # For convenience
    nano man-db curl cron finger bind9-dnsutils \
    # For backend (plumber package)
    libsodium-dev \
    # For magick (downscaling)
    libmagick++-dev gsfonts \
    # For rgl (dependency)
    libgl1-mesa-dev libglu1-mesa-dev \
    # For elliptic
    pari-gp \
    # For sf, terra
    gdal-bin \
    # For keyring
    libsecret-1-dev \
    # For knitr, markdown
    pandoc \
    # For dependencies (s2, fs, rgl)
    libabsl-dev libuv1-dev texlive \
    # Generate SSH key for usage with git
    openssh-client && \
    apt-get -y upgrade && \
    apt-get -y clean && \
    apt-get -y autoremove --purge && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install rust toolchain for gifsky (https://rustup.rs)
# -s -- --no-modify-path -y automates rustup installation without prompts (what `pak` does automatically)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path -y

# Miniforge is now the default used by dgpsi (https://github.com/conda-forge/miniforge#unix-like-platforms-macos-linux--wsl)
RUN mkdir "/shared"
RUN wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" -O "/tmp/miniforge.sh"
RUN bash "/tmp/miniforge.sh" -b -p "${MINIFORGE_PATH}"
RUN rm -f "/tmp/miniforge.sh"
# Debug ---
RUN cat "${MINIFORGE_PATH}/etc/profile.d/conda.sh"
RUN apt update && apt install -y tree
RUN tree "${MINIFORGE_PATH}"
# --- Debug
# source is only available in bash, not sh. Alternative: `. ${MINIFORGE_PATH}/etc/profile.d/conda.sh`
RUN ["/bin/bash", "-c", "source ${MINIFORGE_PATH}/etc/profile.d/conda.sh"]

## Ensure pip is available in that conda environment
#ENV PATH="${MINIFORGE_PATH}/bin:${PATH}"
#ARG CONDA_PLUGINS_AUTO_ACCEPT_TOS="yes"
#RUN "${MINIFORGE_PATH}/bin/conda" create -y \
#    -p "${CONDA_ENV_PATH}" \
#    python \
#    pip

COPY DESCRIPTION_* .
# Install packages in DESCRIPTION files
RUN Rscript -e "install.packages('pak')" && \
    # Rscript -e "pak::pkg_install('github::mingdeyu/dgpsi-R')" && \
    for description_file in DESCRIPTION_*; do \
        echo "NOW WORKING WITH THE DESCRIPTION FILE WITH NAME $description_file" && \
        cp "$description_file" DESCRIPTION && \
        Rscript -e "pak::local_install_dev_deps(upgrade = TRUE)"; \
        rm -f DESCRIPTION "$description_file"; \
    done && \
    rm -rf /tmp/*

# Make conda command available to all
ARG SPECIAL_PATH='$PATH' # do not interpolate $PATH, this is meant to update path in .bashrc
# export PATH="<MINIFORGE_PATH>/bin:$PATH"
RUN echo "export PATH=\"${MINIFORGE_PATH}/bin:${SPECIAL_PATH}\"" | tee -a "/etc/bash.bashrc"

# dgpsi install says:
# To use the package properly, we need to update your R_LD_LIBRARY_PATH.
# Please manually add the following line to your ~/.bashrc:
# export R_LD_LIBRARY_PATH="/shared/miniforge/envs/dgp_si_R_2_6_0_9000/lib${R_LD_LIBRARY_PATH:+:${R_LD_LIBRARY_PATH}}"
# Deyu confirmed that it may lack some dependencies and cannot find the path to those dependencies in the conda env so the path has to be added manually to bash
ARG SPECIAL_PATH='${R_LD_LIBRARY_PATH:+:${R_LD_LIBRARY_PATH}}'
RUN echo "export R_LD_LIBRARY_PATH=\"${MINIFORGE_PATH}/envs/${DGPSI_FOLDER_NAME}/lib${SPECIAL_PATH}\"" | tee -a "/etc/bash.bashrc"

# Tell all R sessions about it (see details in reticulate:::find_conda())
RUN echo "options(reticulate.conda_binary = '${MINIFORGE_PATH}/bin/conda')" | tee -a "/etc/R/Rprofile.site"
ENV RETICULATE_CONDA="${MINIFORGE_PATH}/bin/conda"

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

