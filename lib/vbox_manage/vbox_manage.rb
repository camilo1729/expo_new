require 'cmdctrl'
require 'colorize'
require 'resourceset'
## first classs for Vboxmanagement

def execute_cmd(cmd)
  cmd_int = CtrlCmd.new(cmd)
  cmd_int.run(cmd)
  cmd_int.stdout.each do |line|
    puts line.green
  end
  cmd_int.stderr.each do |line|
    puts line.red
  end
end



class VBoxManage
  ## you have to provide a disk where the appliance is stored
  ## To use it with Kameleon
  # as a constructor we can chose from starting an already machine or creating a new one
  attr_accessor :vmname, :mac, :ip
  
  def initialize(vmname,vmdisk)
    @vmname =vmname
    @vmdisk = vmdisk
    puts "!! Executing VBoxmanage to create the vm machine".green
    puts "!! Registering virtual machine".green    
    execute_cmd("VBoxManage createvm --name #{vmname} --register")
    execute_cmd("VBoxManage storagectl #{@vmname} --name SATA --add sata --controller IntelAhci --bootable on --sataportcount 1")
    execute_cmd("VBoxManage storageattach #{@vmname} --storagectl SATA --port 0 --device 0 --type hdd --medium #{vmdisk}")
    @mac = ""
    @ip = String.new
  end

  def delete
    puts "Deleting virtual machine".green
    execute_cmd("VBoxManage unregistervm #{@vmname} --delete")
  end

  def start(headless=false)
    puts "Starting vm #{@vmname}".green
    if headless
      execute_cmd("VBoxManage startvm  #{@vmname} --type headless")
      else
      execute_cmd("VBoxManage startvm  #{@vmname}")
    end
  end

  def shut_down
    puts "Shutting Down machine".green
    execute_cmd("VBoxManage controlvm  #{@vmname} poweroff")
    sleep 2
  end

  def add(feature)
    case feature
    when "nic1 hostonly"  
      execute_cmd("VBoxManage modifyvm #{@vmname} --nic1 hostonly")
      ## we need to assign a hostonly network
      cmd_temp=`VBoxManage list hostonlyifs | grep Name: | head -n 1`
      host_only_net = cmd_temp.split(" ")[1]
      puts "Assigning #{host_only_net} as hostonly".green
      execute_cmd("VBoxManage modifyvm #{@vmname} --hostonlyadapter1 #{host_only_net}")
      @mac = get_mac_address
    when "nic1 nat"
      execute_cmd("VBoxManage modifyvm #{@vmname} --nic1 nat")
    else
      puts "such feature doesn't exist"
    end
  end

  def add_port(host_port,guest_port)
    
  end

  def set_ip
    ## namp have to be execute it in order to fill the arp table
    return false if @mac.empty? 
    cmd_temp = `VBoxManage list hostonlyifs | grep IPAddress`
    gateway = cmd_temp.split(" ")[1]
    network_address = gateway.sub /(\d{1,3}.\d{1,3}.\d{1,3}).(\d{1,3})/,'\1.*'
    puts "Setting IP -----".green
    system("nmap -sP #{network_address}") 
    cmd_temp = `arp -na | grep #{@mac} | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'`
    @ip = cmd_temp.strip
    if @ip.empty? then
      puts "\t Vms is booting, waiting for 1 sec before retrying".yellow
      sleep 1
      self.set_ip
    else
      puts "\t IP for Vm #{@vmname} is: #{@ip}".green
      return true
    end
  end

  private
  def get_mac_address
    ## This will only work with just one NIC, and called NIC 1
    cmd_temp= `VBoxManage showvminfo #{@vmname} | grep  \"NIC 1:\" | cut -f3 -d ':'`
    temp_mac = cmd_temp.split(",")[0]
    temp_mac.strip! # get rid of blank spaces
    temp_mac.downcase! # downcase to be compatible with UNIX commands
    return temp_mac.scan(/.{2}|.+/).join(":") ## converting to format 88:19:81:AA
  end

end

class VBoxManage_set 
  @name="group of machines"
  attr_accessor :group
  def initialize(vmgroupname,vmdisk,amount)
    @vmgroupname =vmgroupname
    @vmdisk = vmdisk
    @group = []
    puts "!! Executing VBoxmanage to create several machines".green
    puts "!! Creating immutable disk".green
    execute_cmd("VBoxManage modifyhd --type immutable #{@vmdisk}")
 
    amount.times {
      random = (0...8).map{(65+rand(26)).chr}.join      
      ## generates random string.
      @group.push(VBoxManage.new("node_#{random}","#{@vmdisk}"))
      }
  end

  def set_ip
    puts "Setting IP ----- for the set of Vms".green   
    # return false if @group.select{ |vm| vm.mac.empty?}.empty? 
    cmd_temp = `VBoxManage list hostonlyifs | grep IPAddress`
    gateway = cmd_temp.split(" ")[1]
    network_address = gateway.sub /(\d{1,3}.\d{1,3}.\d{1,3}).(\d{1,3})/,'\1.*'
    system("nmap -sP #{network_address}")
    vm_ips = []
    @group.each do |vm|      
      cmd_temp = `arp -na | grep #{vm.mac} | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'`
      cmd_temp = cmd_temp.split("\n")[0] if cmd_temp.include? "\n"
      ## I dont know why it getting two lines
      if not cmd_temp.strip.empty? then
        vm_ips.push(cmd_temp.strip)
        vm.ip = cmd_temp.strip
      end
    end
    if vm_ips.length.to_i == @group.length then
      return true
    else
      puts "\t Vms are booting, waiting for 1 sec before retrying".yellow
      sleep 1
      self.set_ip
      return false
    end
  end

  def method_missing(m, *args, &block)
    if [:mac,:vmname,:start,:shut_down,:delete,:add].include?(m)
      @group.each { |vm|
        vm.send(m,*args)
      }
      # if m==:start then
        
      #   return create_resource_set
      # end
    else
      puts "There's no method called #{m} here -- please try again."  
    end
  end

  def create_resource_set
    ## This method will return a resource set of the set of virtual machines created
    resource_set = ResourceSet::new(:cluster)
    resource_set.properties[:name] = "virtual_set"
    resource_set.properties[:ssh_user] = "root"
    @group.each{ |vm|
      resource = Resource::new(:node, nil, vm.ip.to_s)
      resource.properties[:gateway] = "localhost"
      resource_set.push(resource)
    }
    return resource_set
  end

end
