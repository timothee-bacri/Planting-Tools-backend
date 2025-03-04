FROM r-base:latest

WORKDIR /backend_code

LABEL org.opencontainers.image.source=https://github.com/timothee-bacri/Planting-Tools-backend

ARG CONDA_PATH=/shared/miniconda

# Set dgpsi path version, BUILD ARG
# curl -sSL https://raw.githubusercontent.com/mingdeyu/dgpsi-R/refs/heads/master/R/initi_py.R | grep "env_name *<-" | grep --invert-match "^\s*#" | grep --only-matching --perl-regexp 'dgp.*\d'
ARG DGPSI_FOLDER_NAME

ARG CONDA_ENV_PATH=${CONDA_PATH}/envs/${DGPSI_FOLDER_NAME}
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get -y --no-install-recommends install \
    libcurl4-openssl-dev \
    # packages (devtools, dgpsi)
    libfontconfig1-dev libxml2-dev libudunits2-dev libssl-dev libproj-dev cmake libgdal-dev libharfbuzz-dev libfribidi-dev \
    # Specific to arm64
    libgit2-dev \
    # For RRembo, it depends on eaf
    libgsl-dev libglu1-mesa \
    # For dgpsi
    libtiff-dev libjpeg-dev \
    # needed to install dgpsi via devtools for some reason
    libtool automake \
    # For gifsky
    cargo xz-utils \
    # For convenience
    nano man-db curl cron finger \
    # For backend (plumber package)
    libsodium-dev \
    # Generate SSH key for usage with git
    openssh-client && \
    apt-get -y clean && \
    apt-get -y autoremove --purge && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Miniconda https://docs.anaconda.com/miniconda/
RUN mkdir -p "${CONDA_PATH}"
RUN arch=$(uname -m) && wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh" -O "${CONDA_PATH}/miniconda.sh"
RUN bash "${CONDA_PATH}/miniconda.sh" -b -u -p "${CONDA_PATH}"
RUN rm -f "${CONDA_PATH}/miniconda.sh"

# Install packages while making the image small, and do not reinstall them if they are already there and updated
# RUN Rscript -e "install.packages('remotes', lib = normalizePath(Sys.getenv('R_LIBS_USER')), repos = 'https://cran.rstudio.com/')"

# Packages update once in a while. We (arbitrarily) update them by invalidating the cache monthly
COPY DESCRIPTION .
RUN date +%Y-%m && \
    #Rscript -e "install.packages('remotes')" && \
    #Rscript -e "remotes::install_deps(repos = 'https://cran.rstudio.com')"
    Rscript -e "install.packages('devtools')" && \
    Rscript -e "devtools::install_github('mingdeyu/dgpsi-R')"
RUN rm -f DESCRIPTION

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

# Run plumber
CMD if [ -f /backend_code/backend/trigger_plumber_for_dev.R ]; then \
      Rscript -e /backend_code/backend/trigger_plumber_for_dev.R; \
    else \
      echo "/backend_code/backend/trigger_plumber_for_dev.R not found, doing nothing"; \
      tail -f /dev/null \
    fi
