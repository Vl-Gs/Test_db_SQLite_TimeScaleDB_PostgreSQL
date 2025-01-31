#!/bin/bash

# General configuration variables
WORK_DIR="/path/to/working/directory" # Define the working directory
DUMP_FILE="$WORK_DIR/dump.sql"  # Define the path to the SQL dump file
POSTGRES_PASSWORD="your_postgres_password"    # Define the password for the PostgreSQL 'postgres' user
POSTGRES_USER="your_postgres_user"    # Define the PostgreSQL user to create
POSTGRES_DB="your_database_name"  # Define the PostgreSQL database to create
SSH_KEY_PATH="$WORK_DIR/id_rsa"  # Define the path to the SSH key

# VM configuration variables
VM_NAME="my_vm"  # Define the name of the virtual machine
VM_BOX="ubuntu/bionic64"   # Define the Vagrant box to use
VM_MEMORY="2048"    # Define the memory allocation for the VM (in MB)
VM_CPUS="2"  # Define the number of CPUs for the VM
VM_USER="vagrant_user"  # Define the VM user
VM_PASSWORD="vagrant_password"  # Define the VM user password
VAGRANTFILE="$WORK_DIR/Vagrantfile" # Define the path to the Vagrantfile

# Check if the directory exists
if [ ! -d "$WORK_DIR" ]; then
    echo "Creating directory $WORK_DIR..."
    mkdir -p "$WORK_DIR"
fi

# Check if the dump file exists
if [ ! -f "$DUMP_FILE" ]; then
    echo "ERROR: The dump file '$DUMP_FILE' does not exist in $WORK_DIR"
    echo "Please add the dump file before continuing."
    exit 1
fi

# Generate SSH key
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_PATH" -N ""
fi

# Create Vagrantfile
echo "Creating Vagrantfile..."
cat <<EOF > "$VAGRANTFILE"
Vagrant.configure("2") do |config|
  config.vm.box = "$VM_BOX"
  
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "$VM_MEMORY"  # Adjust memory as needed
    vb.cpus = "$VM_CPUS"  # Adjust CPU count as needed
    vb.name = "$VM_NAME"
  end
  
  config.vm.synced_folder ".", "/vagrant", owner: "vagrant", group: "vagrant"
  
  config.vm.provision "shell", inline: <<-SHELL
    systemctl disable apt-daily.service
    systemctl disable apt-daily.timer
    
    # Install SQLite
    sudo apt update
    sudo apt install -y sqlite3

    # Install PostgreSQL
    sudo apt install -y postgresql-common
    sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
    sudo apt install -y postgresql-17 postgresql-client-17

    # Set password for 'postgres' user (admin)
    echo "Setting password for postgres user..."
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';"

    # Create PostgreSQL user
    echo "Creating PostgreSQL user..."
    sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';"

    # Create PostgreSQL database
    echo "Creating PostgreSQL database..."
    sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

    # Configure PostgreSQL to use $POSTGRES_RAM MB RAM
    sudo sed -i "s/#shared_buffers = 128MB/shared_buffers = ${POSTGRES_RAM}MB/" /etc/postgresql/17/main/postgresql.conf
    sudo sed -i "s/#work_mem = 4MB/work_mem = ${POSTGRES_WORK_MEM}MB/" /etc/postgresql/17/main/postgresql.conf
    sudo sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = ${POSTGRES_MAINTENANCE_WORK_MEM}MB/" /etc/postgresql/17/main/postgresql.conf
    sudo systemctl restart postgresql

    # Install TimescaleDB
    echo "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ jammy main" | sudo tee /etc/apt/sources.list.d/timescaledb.list
    wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg
    sudo apt update
    sudo apt install -y timescaledb-2-postgresql-17 postgresql-client-17

    # Configure TimescaleDB to use $TIMESCALEDB_RAM MB RAM
    sudo sed -i "s/#shared_buffers = 128MB/shared_buffers = ${TIMESCALEDB_RAM}MB/" /etc/postgresql/17/main/postgresql.conf
    sudo sed -i "s/#work_mem = 4MB/work_mem = ${TIMESCALEDB_WORK_MEM}MB/" /etc/postgresql/17/main/postgresql.conf
    sudo sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = ${TIMESCALEDB_MAINTENANCE_WORK_MEM}MB/" /etc/postgresql/17/main/postgresql.conf
    sudo systemctl restart postgresql

    # Install CrateDB
    sudo apt install -y apt-transport-https apt-utils curl gnupg lsb-release
    curl -sS https://cdn.crate.io/downloads/debian/DEB-GPG-KEY-crate | \
        sudo tee /etc/apt/trusted.gpg.d/cratedb.asc
    echo "deb https://cdn.crate.io/downloads/debian/stable/ default main" | \
        sudo tee /etc/apt/sources.list.d/crate-stable.list
    sudo apt update
    sudo apt install -y crate

    # Configure CrateDB to use $CRATEDB_RAM MB RAM
    # Uncomment and adjust the following lines as needed
    # sudo sed -i "s/#heap.size: 1g/heap.size: ${CRATEDB_RAM}m/" /etc/crate/crate.yml
    # sudo sed -i "s/#max_shards_per_node: 2000/max_shards_per_node: ${CRATEDB_MAX_SHARDS}/" /etc/crate/crate.yml
    # sudo systemctl restart crate

    # Create VM user and set password
    sudo useradd -m -s /bin/bash $VM_USER
    echo "$VM_USER:$VM_PASSWORD" | sudo chpasswd

    # Configure SSH access
    sudo mkdir -p /home/$VM_USER/.ssh
    sudo cp /vagrant/id_rsa.pub /home/$VM_USER/.ssh/authorized_keys
    sudo chown -R $VM_USER:$VM_USER /home/$VM_USER/.ssh
    sudo chmod 600 /home/$VM_USER/.ssh/authorized_keys
  SHELL

  config.vm.provision "file", source: "$SSH_KEY_PATH.pub", destination: "/vagrant/id_rsa.pub"
end
EOF

# Check if Vagrant is installed
if ! command -v vagrant &> /dev/null; then
    echo "ERROR: Vagrant is not installed. Please install Vagrant before continuing."
    exit 1
fi

# Check if VirtualBox is installed
if ! command -v VBoxManage &> /dev/null; then
    echo "ERROR: VirtualBox is not installed. Please install VirtualBox before continuing."
    exit 1
fi

# Start the VM
echo "Starting the virtual machine..."
cd "$WORK_DIR"
vagrant up

# Check status
if [ $? -eq 0 ]; then
    echo "The virtual machine has been successfully configured!"
    echo "You can access the virtual machine using the command: vagrant ssh"
    echo "The dump file is available in the VM at: /vagrant/$(basename $DUMP_FILE)"
    echo "SSH key paths:"
    echo "Private key: $SSH_KEY_PATH"
    echo "Public key: $SSH_KEY_PATH.pub"
else
    echo "ERROR: There was a problem starting the virtual machine."
    echo "Check the error messages above."
    exit 1
fi
