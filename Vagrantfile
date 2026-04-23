VAGRANT_IMAGE_NAME = "bento/ubuntu-24.04"

K8S_MASTER_NODES = 3
K8S_WORKER_NODES = 2

K8S_MASTER_IP_START = 10
K8S_WORKER_IP_START = 20
K8S_LB_IP_START = 30

PRIVATE_IP_NW = "10.10.10."
ROUTER_IP_INSIDE_START = 40
ROUTER_IP_OUTSIDE = "192.168.0.40"

Vagrant.configure("2") do |config|
    config.vm.box = VAGRANT_IMAGE_NAME
    config.vm.box_check_update = false
    config.ssh.insert_key = false

    # Provision Load Balancer to make Master Nodes Highly Available
    config.vm.define "k8s-lb" do |lb|
        lb.vm.provider "virtualbox" do |vb|
            vb.name = "k8s-lb"
            vb.memory = 768
            vb.cpus = 1
            vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
            vb.customize ["modifyvm", :id, "--nested-paging","on"]
            vb.customize ["modifyvm", :id, "--nested-hw-virt","on"]
            vb.customize ["modifyvm", :id, "--cpuhotplug","on"]
            vb.customize ["modifyvm", :id, "--audio-driver", "none"]
            vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
            vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
            vb.customize ["modifyvm", :id, "--nictype3", "virtio"]
            vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        end
        lb.vm.hostname = "k8s-lb"
        lb.vm.network :private_network, ip: PRIVATE_IP_NW + "#{K8S_LB_IP_START}"
        lb.vm.provision "ansible" do |ansible|
            ansible.compatibility_mode = "2.0"
            ansible.playbook = "ansible/playbooks/k8s_lb.yml"
            ansible.extra_vars = {
                node_ip: PRIVATE_IP_NW + "#{K8S_LB_IP_START}",
            }
        end
    end

    # Provision Master Nodes
    (1..K8S_MASTER_NODES).each do |i|
        config.vm.define "k8s-master-#{i}" do |node|
            # Name shown in the GUI
            node.vm.provider "virtualbox" do |vb|
                vb.name = "k8s-master-#{i}"
                vb.memory = 2048
                vb.cpus = 2
                vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
                vb.customize ["modifyvm", :id, "--nested-paging","on"]
                vb.customize ["modifyvm", :id, "--nested-hw-virt","on"]
                vb.customize ["modifyvm", :id, "--cpuhotplug","on"]
                vb.customize ["modifyvm", :id, "--audio-driver", "none"]
                vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
                vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
                vb.customize ["modifyvm", :id, "--nictype3", "virtio"]
                vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
                vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
                vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
            end
            node.vm.hostname = "k8s-master-#{i}"
            node.vm.network :private_network, ip: PRIVATE_IP_NW + "#{K8S_MASTER_IP_START + i}"
            node.vm.provision "ansible" do |ansible|
                ansible.compatibility_mode = "2.0"
                if i == 1
                    ansible.playbook = "ansible/playbooks/k8s_master_primary.yml"
                else
                    ansible.playbook = "ansible/playbooks/k8s_master_secondary.yml"
                end
                ansible.extra_vars = {
                    node_ip: PRIVATE_IP_NW + "#{K8S_MASTER_IP_START + i}",
                }
            end
        end
    end

    # Provision Worker Nodes
    (1..K8S_WORKER_NODES).each do |i|
        config.vm.define "k8s-worker-#{i}" do |node|
            node.vm.provider "virtualbox" do |vb|
                vb.name = "k8s-worker-#{i}"
                vb.memory = 1024
                vb.cpus = 1
                vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
                vb.customize ["modifyvm", :id, "--nested-paging","on"]
                vb.customize ["modifyvm", :id, "--nested-hw-virt","on"]
                vb.customize ["modifyvm", :id, "--cpuhotplug","on"]
                vb.customize ["modifyvm", :id, "--audio-driver", "none"]
                vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
                vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
                vb.customize ["modifyvm", :id, "--nictype3", "virtio"]
                vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
                vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
                vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
            end
            node.vm.hostname = "k8s-worker-#{i}"
            node.vm.network :private_network, ip: PRIVATE_IP_NW + "#{K8S_WORKER_IP_START + i}"
            node.vm.provision "ansible" do |ansible|
                ansible.compatibility_mode = "2.0"
                ansible.playbook = "ansible/playbooks/k8s_worker.yml"
                ansible.extra_vars = {
                    node_ip: PRIVATE_IP_NW + "#{K8S_WORKER_IP_START + i}",
                }
            end
        end
    end
    config.vm.define "bird-router" do |router|
       router.vm.provider "virtualbox" do |vb|
            vb.name = "bird-router"
            vb.memory = 512
            vb.cpus = 1
            vb.customize ["modifyvm", :id, "--hwvirtex", "on"]
            vb.customize ["modifyvm", :id, "--nested-paging","on"]
            vb.customize ["modifyvm", :id, "--nested-hw-virt","on"]        
            vb.customize ["modifyvm", :id, "--cpuhotplug","on"]
            vb.customize ["modifyvm", :id, "--audio-driver", "none"]          
            vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
            vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
            vb.customize ["modifyvm", :id, "--nictype3", "virtio"]
            vb.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        end
        router.vm.hostname = "bird-router"
        router.vm.network :public_network, ip: ROUTER_IP_OUTSIDE, netmask: "255.255.255.0"
        router.vm.network :private_network, ip: PRIVATE_IP_NW + "#{ROUTER_IP_INSIDE_START}"
        router.vm.provision "ansible" do |ansible|
            ansible.compatibility_mode = "2.0"
            ansible.playbook = "ansible/playbooks/bird_install.yml"
            ansible.extra_vars = {
                node_ip: PRIVATE_IP_NW + "#{ROUTER_IP_INSIDE_START}",
                router_ip_outside: ROUTER_IP_OUTSIDE,
            }
        end
    end
end
