:local timeout 25
:local spentTime 0
:local spentTimeOnURL 0
:local tgAPIURLforText "https://api.telegram.org/bot123:ABC/sendMessage\3Fchat_id=-123&text="
:local myExternalIP ""

# tunnels
:local vpns { 
    "ovpn-vpn01"
}

# WANs interfaces which to be failovered in the round-robin order
:local interfaces {
  "WAN-Port3-RT"
  "WAN-Port4-Starlink"
  "WAN-Port5-BeeLine"
}

# Check whether Internet is available
:local needINET ( \
     ([:ping 192.5.5.241 interval=1 count=1]=0) \
  && ([:ping 1.1.1.1     interval=1 count=1]=0) \
  && ([:ping 8.8.8.8     interval=1 count=1]=0) \
)

:if ( $needINET = false ) do={
  :quit
  :error "Inet is ok, exiting the failover script"
}

# Start the failover
:log info "AF: Internet is not available"

# Shut down VPNs to avoid hanging routes
:foreach vpn in=$vpns do={ :interface ovpn-client set $vpn disabled=yes }
:log info "AF: stopped VPNs"

# Get the current states and make the next interface to be activated via picking it to $intToEnable
:local foundActiveInterface false
:local intToEnable ($interfaces->0)

:foreach ifname in=$interfaces do={
  :local currentInterface [:interface ethernet find name=$ifname]
  if ( [:interface ethernet get $currentInterface disabled] = false ) do={
    # flag the detection
    :set foundActiveInterface true
    # switch the useless uplink down
    :interface ethernet set $currentInterface disabled=yes
  } else={
    if ( $foundActiveInterface = true ) do={
      # Previous iface was active, so let we push the first disabled interface on the top of the array to implement round-robin activations
      :set foundActiveInterface false
      :set intToEnable $ifname
    }
  }
}

# Start the first link on the list of the disabled interfaces
:interface ethernet set [:interface ethernet find name=$intToEnable] disabled=no
:log info "AF: Interface $intToEnable was activated"

# Get gateway IP
#:local gatewayIP [:ip dhcp-client get [find interface=$intToDisable] gateway]

# Wait for the uplink is ready
:set spentTime 0
:while ( ( $spentTime < $timeout ) \
  && ( ( [:len [:ip dhcp-client get $intToEnable address] ] = 0 ) \ 
      || ( [:interface ethernet get $intToEnable running] = false ) \
  ) \
) do={
  :delay 1s;
  :set spentTime ($spentTime + 1)
}
:log info "AF: Spent $spentTime seconds to get $intToEnable online."

# Uplink is online, so get our VPNs back
:log info "AF: Starting VPNs."
:foreach vpn in=$vpns do={ :interface ovpn-client set $vpn disabled=no }

# Get our new public source IP
:set spentTimeOnURL 0
:while ( ( $spentTimeOnURL < $timeout ) && ( $myExternalIP = "" ) ) do={
  :set myExternalIP ([:tool fetch mode=http output=user url="http://whatismyip.akamai.com" as-value]->"data")
  :delay 1s;
  :set spentTimeOnURL ($spentTimeOnURL + 1)
}
:log info "AF: External IP is $myExternalIP"

# Telegram notification
:local localIP [:ip address get [:ip address find interface=$intToEnable] address]
:local tgURLwithText ($tgAPIURLforText."Switched uplink to: $intToEnable%0AInterface address: $localIP%0AInterface activation took: $spentTime seconds%0APublic source IP is: $myExternalIP")
:tool fetch keep-result=no url=$tgURLwithText
:log info "AF: Requested the URL: $tgURLwithText"
