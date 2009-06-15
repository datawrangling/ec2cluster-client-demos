# Short Ruby example using the ec2cluster REST API and
# the right_aws Amazon S3 module to run a MPI job on EC2
#
# To run the demo:
#
# 1. Set your credentials in config.yml
#
# 2. install the gem dependencies:
#     $ gem install right_http_connection --no-rdoc --no-ri
#     $ gem install right_aws --no-rdoc --no-ri
#     $ gem install activeresource --no-ri --no-rdoc
#
# 3. Run this ruby script
#     $ ruby kmeans.rb
#
# code/Simple_Kmeans.zip - contains the kmeans MPI C source
# we want to compile and execute on the cluster.
#
# code/run_kmeans.sh - bash script executed on EC2
# which unzips the MPI source code, compiles it,
# and runs it on all nodes in the cluster.

require 'rubygems'
require 'activeresource'
require 'right_aws'

# helper method for s3 buckets
def create_bucket(bucketname, s3)
  begin  
    s3.create_bucket(bucketname)
  rescue  
    puts bucketname + ' bucket already exists...'  
  end
end

# ---------------------------------------------------
# Set AWS credentials and ec2cluster service & job info
# ---------------------------------------------------

CONFIG = YAML.load_file("config.yml")

# Specify input data, zip file containing code, and bash script to run the MPI job
sample_input_files = ["input/color100.txt", "code/Simple_Kmeans.zip", 
  "code/run_kmeans.sh"
  ]

# Specify output files produced after command is run on cluster
# You can include path relative to working directory if needed, for example "outputdir/file1.out"
expected_outputs = ["color100.txt.membership", "color100.txt.cluster_centres"]

# Indicate desired output path, if any:
out_path = "output/#{Time.now.strftime('%m%d%y%H%M')}/"

# ---------------------------------------------------
# Upload Input files to Amazon S3
# ---------------------------------------------------

# Create a connection to Amazon S3 using the right_aws gem
s3handle = RightAws::S3Interface.new(CONFIG['aws_access_key_id'],
            CONFIG['aws_secret_access_key'], {:multi_thread => true})


# If input and output buckets don't exist, create them:
puts "Creating S3 buckets..."
create_bucket(CONFIG['inputbucket'], s3handle)
create_bucket(CONFIG['outputbucket'], s3handle)

s3infiles = []

# Upload the input files and code to S3:
puts "Uploading files to S3"
sample_input_files.each do |infile|
  puts "uploading: " + infile
  s3handle.put(CONFIG['inputbucket'], infile, File.open(infile))
  # keep full s3 path for later
  s3infiles << CONFIG['inputbucket'] + "/" + infile
end

# ---------------------------------------------------
# Submit the MPI Job
# ---------------------------------------------------

puts "Running Job command..."
# Use ActiveResource to communicate with the ec2cluster REST API
class Job < ActiveResource::Base
  self.site = CONFIG['rest_url']  
  self.user = CONFIG['admin_user']
  self.password = CONFIG['admin_password']
  self.timeout = 5
end

# Submit a job request to the API using just the required parameters
job = Job.new(:name => "Kmeans demo", 
  :description => "Simple Kmeans C MPI example", 
  :input_files => s3infiles.join(" "), 
  :commands => "bash run_kmeans.sh", 
  :output_files => expected_outputs.join(" "), 
  :output_path => CONFIG["outputbucket"] + "/" + out_path, 
  :number_of_instances => "3", 
  :instance_type => "m1.small")

puts job.to_s
job.save # Saving submits the job description to the REST service  
job_id = job.id

puts "Job ID: " + job.id.to_s # returns the job ID
puts "State: " + job.state # current state of the job
puts "Progress: " + job.progress unless job.progress.nil? # more granular description of the current job progress

# Some examples of other optional parameters for Job.new()
# ------------------------------------
# master_ami => "ami-bf5eb9d6"
# worker_ami => "ami-bf5eb9d6"
# user_packages => "python-setuptools python-docutils"
# availability_zone => "us-east-1a"
# keypair => CONFIG["keypair"]
# mpi_version => "openmpi"
# shutdown_after_complete => false

# Loop, waiting for the job to complete.  
puts "Waiting for job to complete..."
until job.state == 'complete' do
  begin   
    job = Job.find(job_id)
    puts "[State]: " + job.state + " [Progress]: " + job.progress unless job.progress.nil?
  rescue ActiveResource::TimeoutError  
    puts "TimeoutError calling REST server..."  
  end
  sleep 5  
end

# Wrap this with error handling for real job submissions
# and cancel job if it takes to long..
# A cancellation can be sent as follows:  job.put(:cancel)

# ---------------------------------------------------
# Download Output Files from S3
# ---------------------------------------------------
puts "Job complete, downloading results from S3"
# If the job finished successfully, fetch the output files from our S3 bucket
expected_outputs.each do |outfile|
  puts "fetching: " + outfile
  filestream = File.new(outfile, File::CREAT|File::RDWR)
  rhdr = s3handle.get(CONFIG['outputbucket'], out_path + outfile) do |chunk| filestream.write(chunk) end
  filestream.close  
end





