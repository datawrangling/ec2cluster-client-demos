#!/bin/bash

# simple script to compile and run opnempi kmeans code
# CPU_COUNT environment variable and openmpi_hostfile will be available when the job runs

# first we unzip our MPI code & compile
unzip Simple_Kmeans.zip
cd Simple_Kmeans
make
cd ../
# Next we run the actual MPI command
# this sample MPI program "mpi_main" takes an input file and number of centroids as arguments, then runs kmeans in parallel
# The command will produce two output files in the working directory: color100.txt.membership & color100.txt.cluster_centres
mpirun -np $CPU_COUNT --hostfile /home/ec2cluster/openmpi_hostfile /home/ec2cluster/Simple_Kmeans/mpi_main -i color100.txt -n 3
