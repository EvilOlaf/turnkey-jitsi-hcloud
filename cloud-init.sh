#!/bin/bash
# hcloud server create --datacenter 4 --image 40093140 --name jitsi1 --type cpx41 --primary-ipv4 12345678 --primary-ipv6 12345679 --user-data-from-file cloud-init.sh

export DOMAIN=your.own.domain.example.com
export EMAIL=youremail@example.com

export CHAIRNAME=yournickname
export CHAIRPW=arandompassword


#######################################

# start public config
JIBRIPW="$(cat /dev/urandom | tr -dc a-zA-Z | head -c10)"
RECORDERPW="$(cat /dev/urandom | tr -dc a-zA-Z | head -c10)"

#dirty hacks around hetzner script
sed -i -e 's/.*read\ -p\ \"Is.*$/break/g' /opt/hcloud/jitsi_setup.sh
sed -i -e 's/.*read\ -p\ \"Note.*$/le=n/g' /opt/hcloud/jitsi_setup.sh
export DEBIAN_FRONTEND=noninteractive
export domain=$DOMAIN; /opt/hcloud/jitsi_setup.sh
#/usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh $EMAIL $DOMAIN
# end public config

apt update
apt upgrade -y

# start enable auth
sed -i 's/jitsi-anonymous/internal_hashed/g' /etc/prosody/conf.avail/$DOMAIN.cfg.lua 
sed -i "/recorder.$DOMAIN/a VirtualHost \"guest.$DOMAIN\"\n\ \ authentication = \"anonymous\"\n\ \ c2s_require_encryption = false" /etc/prosody/conf.avail/$DOMAIN.cfg.lua
sed -i -e "s/.*anonymousdomain.*/\ \ \ \ \ \ \ \ anonymousdomain:\ \x27guest.$DOMAIN\x27,/g" /etc/jitsi/meet/$DOMAIN-config.js
sed -i "/jicofo\ {/a \ \ authentication:\ {\n\ \ \ \ enabled:\ true\n\ \ \ \ type:\ XMPP\n\ \ \ \ login-url:\ $DOMAIN\n\ \ }" /etc/jitsi/jicofo/jicofo.conf

prosodyctl register $CHAIRNAME $DOMAIN $CHAIRPW
systemctl restart prosody
systemctl restart jicofo
systemctl restart jitsi-videobridge2
# end enable auth

# start enable recording
apt install linux-image-generic-hwe-20.04 -y
echo "snd-aloop" >> /etc/modules
curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
apt update
apt install -y google-chrome-stable
mkdir -p /etc/opt/chrome/policies/managed
echo ‘{ “CommandLineFlagSecurityWarningsEnabled”: false }’ >>/etc/opt/chrome/policies/managed/managed_policies.json
CHROME_DRIVER_VERSION=`curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE` && wget -N http://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip -P ~/
unzip ~/chromedriver_linux64.zip -d ~/
rm ~/chromedriver_linux64.zip
mv -f ~/chromedriver /usr/local/bin/chromedriver
chown root:root /usr/local/bin/chromedriver
chmod 0755 /usr/local/bin/chromedriver
apt-get install ffmpeg curl alsa-utils icewm xdotool xserver-xorg-input-void xserver-xorg-video-dummy -y

apt install jibri -y
usermod -aG adm,audio,video,plugdev jibri

cat >> /etc/prosody/conf.avail/$DOMAIN.cfg.lua << EOF
-- internal muc component, meant to enable pools of jibri and jigasi clients
Component "internal.auth.$DOMAIN" "muc"
    modules_enabled = {
        "ping";
    }
    storage = "memory"
    muc_room_cache_size = 1000
    
VirtualHost "recorder.$DOMAIN"
    modules_enabled = {
        "ping";
    }
    authentication = "internal_plain"
EOF

prosodyctl register jibri auth.$DOMAIN $JIBRIPW
prosodyctl register recorder recorder.$DOMAIN $RECORDERPW
hocon -f /etc/jitsi/jicofo/jicofo.conf set jicofo.jibri.brewery-jid "\"JibriBrewery@internal.auth.$DOMAIN\""
hocon -f /etc/jitsi/jicofo/jicofo.conf set jicofo.jibri.pending-timeout "90 seconds"

sed -i -e "/var config/a\ \ \ \ hiddenDomain:\ \x27recorder.$DOMAIN\x27," /etc/jitsi/meet/$DOMAIN-config.js
sed -i -e 's/\/\/\ liveStreaming:\ {/liveStreaming: {/' /etc/jitsi/meet/$DOMAIN-config.js
sed -i '/liveStreaming:\ {/a \ \ \ \ \ \ \ \ \ \ enabled:\ true,\n\ \ \ \ },' /etc/jitsi/meet/$DOMAIN-config.js
sed -i -e 's/\/\/\ recordingService:\ {/recordingService: {/' /etc/jitsi/meet/$DOMAIN-config.js
sed -i '/recordingService:\ {/a \ \ \ \ \ \ \ \ \ \ enabled:\ true,\n\ \ \ \ },' /etc/jitsi/meet/$DOMAIN-config.js

mkdir /srv/recordings
chown jibri:jibri /srv/recordings

ID="$(cat /dev/urandom | tr -dc a-zA-Z | head -c10)"
cat > /etc/jitsi/jibri/jibri.conf << EOF
jibri {
id = "$ID"
single-use-mode = false
api {
http {
external-api-port = 2222
internal-api-port = 3333
 }
xmpp {
environments = [
{
name = "prod environment"
xmpp-server-hosts = ["$DOMAIN"]
xmpp-domain = "$DOMAIN"


            control-muc {
                domain = "internal.auth.$DOMAIN"
                room-name = "JibriBrewery"
                nickname = "jibri-nickname"
            }

            control-login {
                domain = "auth.$DOMAIN"
                username = "jibri"
                password = "$JIBRIPW"
            }

            call-login {
                domain = "recorder.$DOMAIN"
                username = "recorder"
                password = "$RECORDERPW"
            }

            strip-from-room-domain = "conference."
            usage-timeout = 0
            trust-all-xmpp-certs = true
         }
      ]
   }
 }
recording {
recordings-directory = "/srv/recordings"
finalize-script = "/upload.sh"
 }
streaming {
rtmp-allow-list = [
".*"
   ]
 }
ffmpeg {
resolution = "1920x1080"
audio-source = "alsa"
audio-device = "plug:bsnoop"
 }
chrome {
flags = [
"--use-fake-ui-for-media-stream",
"--start-maximized",
"--kiosk",
"--enabled",
"--disable-infobars",
"--autoplay-policy=no-user-gesture-required",
"--ignore-certificate-errors"
   ]
 }
stats {
enable-stats-d = true
 }
webhook {
subscribers = []
 }
jwt-info {
# signing-key-path = "/path/to/key.pem"
# kid = "key-id"
# issuer = "issuer"
# audience = "audience"
# ttl = 1 hour

 }
call-status-checks {
no-media-timeout = 30 seconds
all-muted-timeout = 10 minutes
default-call-empty-timeout = 30 seconds

   }
}
EOF

# TODO: Write upload
cat > /upload.sh << EOF
#!/bin/bash
echo add automatic uploading of meeting file to somewhere at the end
exit 0
EOF
# end enable recording

# some system stuff
systemctl enable jibri
fallocate -l 2G /swap
mkswap /swap
chmod 600 /swap
swapon /swap
echo "/swap    none    swap    sw      0 0" >> /etc/fstab
reboot now

