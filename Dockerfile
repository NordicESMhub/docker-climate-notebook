# Jupyter container used for Galaxy IPython (+other kernels) Integration
FROM jupyter/scipy-notebook:d990a62010ae

MAINTAINER Björn A. Grüning, bjoern.gruening@gmail.com

ENV DEBIAN_FRONTEND noninteractive

# Install system libraries first as root
USER root

RUN apt-get -qq update && apt-get install --no-install-recommends -y libcurl4-openssl-dev libxml2-dev \
    apt-transport-https python-dev libc-dev pandoc pkg-config liblzma-dev libbz2-dev libpcre3-dev \
    build-essential libblas-dev liblapack-dev gfortran libzmq3-dev libyaml-dev libxrender1 fonts-dejavu \
    libfreetype6-dev libpng-dev net-tools procps libreadline-dev wget software-properties-common octave \
    ca-certificates wget vim subversion sshfs openssh-client \
    # IHaskell dependencies
    zlib1g-dev libtinfo-dev libcairo2-dev libpango1.0-dev && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

USER $NB_USER

# Install requirements for Python 3
ADD climate_environment.yml climate_environment.yml

# Python packages
RUN conda update -n base conda && conda env update -f climate_environment.yml && conda clean -yt && \
    pip install --no-cache-dir bioblend galaxy-ie-helpers nbgitpuller \
               ipydatawidgets sidecar geojsoncontour \
               pysplit

# Install requirements for cesm 
ADD esmvaltool_environment.yml esmvaltool_environment.yml
RUN conda create --name esmvaltool

RUN ["/bin/bash" , "-c", ". /opt/conda/etc/profile.d/conda.sh && \
    conda activate esmvaltool && \
    mkdir -p /opt/conda/envs/esmvaltool/src && \
    mkdir -p /opt/conda/envs/esmvaltool/bin && \
    wget https://julialang-s3.julialang.org/bin/linux/x64/1.5/julia-1.5.3-linux-x86_64.tar.gz && \
    tar zxvf julia-1.5.3-linux-x86_64.tar.gz --directory /opt/conda/envs/esmvaltool/src && \
    ln -s /opt/conda/envs/esmvaltool/src/julia-1.5.3/bin/julia /opt/conda/envs/esmvaltool/bin/julia  && \
    conda env update --file esmvaltool_environment.yml && \
    conda deactivate"]

# Install requirements for eclimate 
ADD cmor_environment.yml cmor_environment.yml

# Python packages
RUN conda env create -f cmor_environment.yml && conda clean -yt

ENV CMOR_ROOT=/opt/conda/pkgs/noresm2cmor-3.0.1
RUN ["/bin/bash" , "-c", ". /opt/conda/etc/profile.d/conda.sh && \
    conda activate cmor && \
    git clone https://github.com/EC-Earth/ece2cmor3.git && \
    cd ece2cmor3 && \
    git submodule update --init --recursive && \
    python setup.py install && \
    cd .. && rm -rf ece2cmor3 && \
    cd /opt/conda/pkgs && \
    wget https://github.com/NordicESMhub/noresm2cmor/archive/v3.0.1.tar.gz --no-check-certificate && \
    tar zxf v3.0.1.tar.gz && \
    cd noresm2cmor-3.0.1/build && \
    make -f Makefile_cmor3.jh_gnu && \
    make -f Makefile_cmor3mpi.jh_gnu && \
    rm -rf ../v3.0.1.tar.gz && \
    rm -rf *.o *.mod && \
    cp ../bin/noresm2cmor3  ../bin/noresm2cmor3_mpi /opt/conda/envs/cmor/bin/ && \
    conda deactivate"]

# Install requirements for cesm 
ADD cesm_environment.yml cesm_environment.yml

# Python packages
RUN conda env create -f cesm_environment.yml && conda clean -yt && \
    mkdir -p /home/jovyan/.cime

ADD config_compilers.xml /home/jovyan/.cime/config_compilers.xml
ADD config /home/jovyan/.cime/config
ADD config_machines.xml /home/jovyan/.cime/config_machines.xml

ADD ./startup.sh /startup.sh
ADD ./get_notebook.py /get_notebook.py

# We can get away with just creating this single file and Jupyter will create the rest of the
# profile for us.
RUN mkdir -p /home/$NB_USER/.ipython/profile_default/startup/ && \
    mkdir -p /home/$NB_USER/.jupyter/custom/

COPY ./ipython-profile.py /home/$NB_USER/.ipython/profile_default/startup/00-load.py
COPY jupyter_notebook_config.py /home/$NB_USER/.jupyter/
COPY jupyter_lab_config.py /home/$NB_USER/.jupyter/

ADD ./custom.js /home/$NB_USER/.jupyter/custom/custom.js
ADD ./custom.css /home/$NB_USER/.jupyter/custom/custom.css
ADD ./default_notebook.ipynb /home/$NB_USER/notebook.ipynb

# ENV variables to replace conf file
ENV DEBUG=false \
    GALAXY_WEB_PORT=10000 \
    NOTEBOOK_PASSWORD=none \
    CORS_ORIGIN=none \
    DOCKER_PORT=none \
    API_KEY=none \
    HISTORY_ID=none \
    REMOTE_HOST=none \
    GALAXY_URL=none


# Install the Dask dashboard
RUN pip install dask-labextension

# Dask Scheduler & Bokeh ports
EXPOSE 8787
EXPOSE 8786

RUN jupyter labextension install @jupyterlab/geojson-extension @jupyterlab/toc-extension @jupyterlab/katex-extension @jupyterlab/fasta-extension @jupyterlab/git

RUN jupyter labextension install @jupyterlab/hub-extension @jupyter-widgets/jupyterlab-manager && \
    jupyter labextension install jupyter-leaflet jupyterlab-datawidgets nbdime-jupyterlab dask-labextension && \
    jupyter labextension install @jupyter-widgets/jupyterlab-sidecar && \
    jupyter serverextension enable jupytext && \
    jupyter nbextension install --py jupytext --user && \
    jupyter nbextension enable --py jupytext --user && \
    jupyter labextension install @jupyterlab/geojson-extension

USER root

ADD pangeo64x64.png /opt/conda/share/jupyter/kernels/python3/logo-64x64.png 
RUN chmod 664 /opt/conda/share/jupyter/kernels/python3/logo-64x64.png
ADD pangeo32x32.png /opt/conda/share/jupyter/kernels/python3/logo-32x32.png 
RUN chmod 664 /opt/conda/share/jupyter/kernels/python3/logo-32x32.png

RUN apt-get -qq update && \
    apt-get install -y net-tools procps && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# /import will be the universal mount-point for Jupyter
# The Galaxy instance can copy in data that needs to be present to the Jupyter webserver
RUN mkdir -p /import/jupyter/outputs/ && \
    mkdir -p /import/jupyter/data && \
    mkdir /export/ && \
    chown -R $NB_USER:users /home/$NB_USER/ /import /export/

WORKDIR /import

# Start Jupyter Notebook
CMD /startup.sh
