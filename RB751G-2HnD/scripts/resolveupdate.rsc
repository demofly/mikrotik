
:local dhcpif1name "MAN-Port5-ISP3"
:local dhcpif1gw [:ip dhcp-client get $dhcpif1name gateway]

:local tun1name "WAN-L2TP-ISP3"
:local tun2name "WAN-PPPoE-ISP4"

:local tun1up [:interface l2tp-client get $tun1name running]
:local tun2up [:interface pppoe-client get $tun2name running]

:local tun1 [:interface l2tp-client find name=$tun1name]
:local tun2 [:interface pppoe-client find name=$tun2name]

# Our permanently available DNS servers from the third WAN with no tunnels - could be even empty. 
# Also it is a suitable place to add google DNS server like 8.8.8.8.
:local ISP2DNS {
    10.99.0.1;
    10.99.0.2
}
:local DNS
:local DNSok {}
:local CurrDNS [:ip dns get servers]

# Build an actual list of available DNS servers
foreach DNS in=($ISP2DNS, $CurrDNS) do={
    if ( ( [:tostr [:find $DNSok $DNS]]="" ) && ( [:ping $DNS interval=1 count=2]>0 ) ) do={
# I know, ping is a really bad way to check a DNS server works, but I don't see a better way for Mikrotik.
        :set DNSok ($DNSok, $DNS)
    }
}

# If the old list differs, let we update it:
if ( $DNSok!=$CurrDNS ) do={
  :log info "Changing DNS servers to $DNSok"
  :ip dns set servers=$DNSok
}

:if ( ( [:interface ethernet get $dhcpif1name running] = true ) && ( [:interface l2tp-client get $tun1name disabled] = false ) ) do={
    :local ToBeReRouted {
        [:tostr [:ip dhcp-client get $dhcpif1name primary-dns] ] . "/32";
        [:tostr [:ip dhcp-client get $dhcpif1name secondary-dns] ] . "/32"
    }
    foreach DNS in=$ToBeReRouted do={
        if ( ( [:len [:ip route find dst-address=$DNS] ]>0 ) && ( [:len [:ip route find dst-address=$DNS gateway=$dhcpif1gw] ]=0 ) ) do={
          :ip route remove [:ip route find dst-address=$DNS]
        }
        if ( [:len [:ip route find dst-address=$DNS] ]=0 ) do={
          :ip route add comment=ISP3DNS disabled=no dst-address=$DNS gateway=$dhcpif1gw
        }
    }

    if ( ( $tun1up = false ) || ( $tun2up = true ) ) do={
        :set CurrDNS [:ip dns get servers]
        :local TmpDNS {
            [:ip dhcp-client get $dhcpif1name primary-dns];
            [:ip dhcp-client get $dhcpif1name secondary-dns] 
        }
        :log info "Changing DNS servers to $TmpDNS to resolve VPN server:"
        :ip dns set servers=$TmpDNS
        :ip dns cache flush
        :local newIP [:resolve vpn.isp-example.ru]
        :log info "Reverting DNS servers to $CurrDNS:"
        :ip dns set servers=$CurrDNS
        :local oldIP [:interface l2tp-client get $tun1 connect-to]
        :local oldIPstr "$oldIP/32"
        if ( ($oldIP != $newIP) && ($newIP != "") ) do={
            if ( [:len [:ip route find comment=ISP3ServerVPN] ]>0 ) do={
                :ip route remove [:ip route find comment=ISP3ServerVPN]
            }
            if ( [:len [:ip route find dst-address=$oldIPstr] ]>0 ) do={
                :ip route remove [:ip route find dst-address=$oldIPstr]
            }
            if ( [:len [:ip route find dst-address=$newIP] ]=0 ) do={
                :ip route add comment=ISP3ServerVPN disabled=no dst-address=$newIP gateway=$dhcpif1gw
            }
            :log info "Set $tun1name connect-to: $newIP."
            :interface l2tp-client set $tun1 connect-to=$newIP
        }
    }
}