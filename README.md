# turnkey-jitsi-hcloud


## tl;dr
Turnkey Jitsi instance in Hetzner cloud with existing IPs/Domain for spontaneous recurring meetings.

- Comes with anonymous meetings disabled, login credentials for the host
- Comes with recording feature enabled

## The long version

### Requirements

- A domain name (must support A/AAAA records)
- (primary) IPv4/IPv6 addresses created beforehand in Hetzner Cloud

### First time setup

- To go your Hetzner cloud panel and create both a primary IPv4 address and IPv6 address. I recommend to activate protection for both to avoid accidental deletion on instance removal.
- Once that is done create identical A and AAAA records. Use the first address of your /64 prefix, `::1` to say, for latter.
- Now you need the `hcloud` tool. After activating it with a token lookup the IDs of your IP addresses as you will need them later.  
For reference check here: <https://github.com/hetznercloud/cli>

__Make sure the lookup for your DNS records works before you proceed.__ Have a big cup of coffee, go for a walk or sleep a night over.

Download the `cloud-init.sh` from this repository and make adjustments as you like.
Then start the deployment.  

```bash
# replace IDs for your IP addresses
hcloud server create --datacenter 4 --image 40093140 --name jitsi1 --type cpx41 --primary-ipv4 12345678 --primary-ipv6 12345679 --user-data-from-file cloud-init.sh
```

<details>
  <summary>Command breakdown</summary>
  
- `--datacenter` replace the ID if you want a datacenter closer to you, like in the United States. `4` is Falkenstein, Germany.  
- `--image` at the moment of creating this script 40093140 was the app image for Jitsi on amd64 architecture.  
- `--name` A random name for your server.  
- `--type` the instance type to be created. If you do not plan to record `cpx21` or even `cpx11` should work just fine.  
For recording however we need much more power since video encoding will be done by the CPU. Use `cpx41` in this case.
- `--primary-ipv4` and `--primary-ipv6` are the IDs of your IP addresses you configured beforehand.  
- `--user-data-from-file` pass all the commands in the script to cloud-init to be executed immediately after server creation.

</details>  
  
  
The setup process takes about 5 minutes after command was entered. The cloud server will restart once setup is complete. Until then just leave it or watch the process by checking `/var/log/cloud-init-output.log`.  

**ATTENTION**: If you login while the setup is performing you might be greeted with the Hetzner Jitsi install script asking for a domain name. DO NOT ENTER ANYTHING. Simply hit `^C` (CTRL+C) to drop into shell.

After that you should be able to navigate to https://your.domain and once you start a meeting you can login with the credentials defined in the script earlier.

Once your meeting is done use `hcloud server delete 123456789` to get rid of the instance. If you did a recording download it beforehand like with `scp`.  
Use `hcloud server list` to determ the instance ID.

### Recurring setup

Use the same `hcloud server create`  and `hcloud server delete` commands as before and you're set.

### Why?

Recently the so called BigBrotherAwards have been awarded. In the pool of winners this year were also the well known Zoom video conference tool. This made me thinking, because the Armbian project uses Zoom for their weekly developer meetups.

So I decided to invest a bit of time to explore if it would be possible to deploy a self-hosted Jitsi video-conference server on a Hetzner cloud server on demand, without much configuration needed.

Fortunately Hetzner already did some work and provides an app image for deploying Jitsi. However this only setups Jitsi without recording and/or credentials and furthermore needs user interaction. These interaction needed some dirty hacks to work around.

Having these Jitsi instances created on demand saves a lot of money in comparison to having an instance running a full month.  
Basically cost are 60ct per month for the IPv4 address plus a few cents per hour for actual meeting.  

For example. A CPX41 instance cost is about 4ct/hour. This adds up to 28€ per month if running continuously. If however we have one meeting per week which let's say take two to three hours each time each meeting costs about 8 to 12 cents or 48 cents per month at most.

### Closing

I published the early stage and idea on my website: https://zuckerbude.org/hetzner-jitsi/

### Some technical details or DAFUQ DID YOU DO!?

- By default the Hetzner Jitsi install script does the certbot stuff as well but as you can see I decided against hacking around it (see `sed -i -e 's/.*read\ -p\ \"Note.*$/le=n/g'`). The reason is that the nice guys included the option to issue the certificate later on using the `install-letsencrypt-cert.sh` which allows the usage of parameters.
- The default kernel oddly does not come with `snd-aloop` module even though it is configured in the config file. I decided to not waste time for research but simply install the latest Focal hwe generic kernel which has everything I needed. This is also the reason why the restart is necessary.