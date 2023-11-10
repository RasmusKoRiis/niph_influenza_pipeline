#!/bin/bash
#Pipline for generation of Influenza A + B whole genome sequences, 
#including analysis producing mutation calling, vaccine-contamination protocols and more....

export INFLUENZA_V1_VERSION="1.0"
export LAB_PROTOCOL=""

#COMMAND LINE OPTIONS
while getopts ":i:dh" opt; do
  case ${opt} in
    i )
      run_folder=${OPTARG}
      ;;
    d )
      demultiplexing=TRUE
      ;;
    h )
      echo "Usage: ./master.sh -i [input_file] [-d]"
      echo ""
      echo "Options:"
      echo "i    Specify the input file (required)"
      echo "d    Specify if samples should be demultiplexed"
      echo "h    Display this help message"
      exit 0
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." 1>&2
      exit 1
      ;;
  esac
done

if [ -z "$run_folder" ]; then
  echo "Error: You must specify an input file with the -i option"
  exit 1
fi

#SETS BASEDIR
basedir=$(pwd)

#DOWNLOAD SCRIPT
git clone https://github.com/RasmusKoRiis/INFLUENZA_GENOME_ANALYSIS.git

#CHECK INPUT FOLDER
if [ ! -d "$run_folder" ]; then
  echo "$run_folder does not exist, creating it and running rsync"
  ip_address=X
  mkdir "${run_folder}_data"
  cd "${run_folder}_data"
  rsync -avr --exclude '*.fast5' grid@${ip_address}:/data/${run_folder}/* ./
  cd "$basedir"  # Make sure to return to the initial directory

  # Locate the fastq_pass directory nested inside ${run_folder}_data
  fastq_pass_dir=$(find "$(pwd)/${run_folder}_data" -type d -name 'fastq_pass' -print -quit)
  if [[ -n "$fastq_pass_dir" ]]; then
    mv "$fastq_pass_dir" "$basedir/"
  fi
else 
  echo "fastq_pass directory found"
  fastq_pass_dir=$(find "$(pwd)/${run_folder}" -type d -name 'fastq_pass' -print -quit)
fi

echo "The run folder is $fastq_pass_dir"
cd $fastq_pass_dir

#UNZIP FASTQ FILES
for dir in */; do
  # Check if the directory contains any *.fastq.gz files
  if ls "$dir"*.fastq.gz 1> /dev/null 2>&1; then
    # Go inside the directory
    cd "$dir"
    # Unzip all *.fastq.gz files
    gunzip *.fastq.gz
    # Return to the parent directory
    cd ..
  fi
done

cd "$basedir" 

#RENAME FASTQ FOLDERS
python3 INFLUENZA_GENOME_ANALYSIS/script_files/rename_fastq_folders.py $fastq_pass_dir *csv


find "$fastq_pass_dir" -type f -or -type d -name "*barcode*" -exec rm -rf {} \;
find "$fastq_pass_dir" -type f -or -type d -name "*unclassified*" -exec rm -rf {} \;
#cp -a $fastq_pass_dir INFLUENZA_GENOME_ANALYSIS 
cd INFLUENZA_GENOME_ANALYSIS
#mv $fastq_pass_dir input_fastq_processed
#input_fastq_processed=input_fastq_processed


#TECHNICAL INFO OF PIPLINE
date=$(date +"%Y-%m-%d_%H-%M-%S")
startdir=$(pwd)
script="$startdir/script_files"
runname=$(basename $startdir)
script_name=

#FOLDER FOR RESULTS AND SEQUENCES
mkdir results
cd results
mkdir fasta bam stat mutation

cd $startdir

result_folder="$startdir/results"
fasta_folder="$result_folder/fasta"
bam_folder="$result_folder/bam"
stat_folder="$result_folder/stat"
mutation_folder="$result_folder/mutation"
dataset_folder="$startdir/dataset"
reference="$startdir/references"

cd $startdir


#PRE POCESSING

# Build the QA-Docker image
image_name_qa="new_influensa_pipeline_qa_v1_3"
container_name_qa="influenza_qa_container_v0_1"
docker_file_qa="Dockerfile.QA"  

#CHECK IF IRMA SHOULD RUN

# EPI2ME NEXTFLOW 
nextflow run epi2me-labs/wf-flu -r v0.0.6 --fastq $fastq_pass_dir/  --out_dir $result_folder/epi2me_wf_flu_output --min_qscore 10  --min_coverage 50 --reference "$startdir/references/epi2me/reference_epi2me_FULL_NAMES.fasta" 

cd $startdir

container_name="influenza_container"
image_name="new_influensa_pipeline_v0.5"

docker buildx build --platform linux/amd64 -t $image_name .

# Run the Docker container to execute the rest of the pipeline and copy the results
docker run --rm -it --name $container_name \
  -v $startdir/results_docker:/results_docker \
  -e RUNNAME=$run_folder -e INFLUENZA_V1_VERSION=INFLUENZA_V1_VERSION  \
  $image_name bash -c "script_files/master_NF.sh && cp -r /app/results /results_docker"


#Copy and clean up folders
cd $basedir
cp -r $runname/results_docker/results $basedir
mv results "${run_folder}_results"
cp "${run_folder}_results"/stat/"${run_folder}_summary.csv" $basedir



cd /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/Ses2324/results
echo ngs3 | sudo cp -r $basedir/results /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/Ses2324/results
cd /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/Ses2324/powerBI
echo ngs3 | sudo cp $basedir/results/stat/*_summary.csv /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/Ses2324/powerBI

#rm -r INFLUENZA_GENOME_ANALYSIS

