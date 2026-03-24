# he-ddns-update-v8
# RouterOS 7.x  |  Hurricane Electric DDNS

# --- Глобальная переменная — кеш последнего отправленного IP ---
:global lastIP

# --- Локальные сущности ---
:local ddnshost "router1.example.com"
:local ddnspass "YourDDNSpassword123"
:local waniface "WAN2"
:local ddnsurl  "https://dyn.dns.he.net/nic/update"

# --- Получаем список ID адресов на интерфейсе ---
:local addrList [:ip address find interface=$waniface]

:if ([:len $addrList] = 0) do={
    :log error ("DDNS for HE.net: no IPv4 address found on $waniface")
} else={
    :local rawIP [:ip address get [:pick $addrList 0] address]
    :local currentIP [:pick $rawIP 0 [:find $rawIP "/"]]

    :if ($currentIP = "") do={
        :log error ("DDNS for HE.net: cannot split data [$rawIP] with '/'")
    } else={
        # Если глобальная переменная потеряна (перезагрузка), восстанавливаем из DNS
        :if ([:typeof $lastIP] = "nothing") do={
            :do {
                :local resolved [:resolve $ddnshost]
                :set lastIP $resolved
            } on-error={
                :log warning ("DDNS for HE.net: cannot resolve $ddnshost to seed lastIP cache")
            }
        }

        :if ($lastIP = $currentIP) do={
            :log info ("DDNS for HE.net: nothing to change in the $ddnshost IN A record, skipping an update")
        } else={
            :log info ("DDNS for HE.net: I've got a new IP address: [$currentIP]")

            # --- Отправляем обновление ---
            :local body ("hostname=" . $ddnshost . "&password=" . $ddnspass . "&myip=" . $currentIP)

            :do {
                :local result [/tool fetch  \
                    mode=https              \
                    url=$ddnsurl            \
                    http-method=post        \
                    http-data=$body         \
                    output=user             \
                    as-value]

                :if ($result->"status" != "finished") do={
                    :log error ("DDNS for HE.net: DDNS UPDATE request FAILED, status=" . ($result->"status"))
                } else={
                    :local resp ($result->"data")
                    :log info ("DDNS for HE.net: DDNS server response: [$resp]")

                    # HE.net возвращает "good <ip>" или "nochg <ip>" при успехе
                    :if (([:find $resp "good"] != nil) or \
                         ([:find $resp "nochg"] != nil)) do={
                        :set lastIP $currentIP
                        :log info ("DDNS for HE.net: updated $ddnshost IN A with [$currentIP]")
                    } else={
                        :log error ("DDNS for HE.net: update rejected by server: [$resp]")
                    }
                }
            } on-error={
                :log error ("DDNS for HE.net: fetch failed (network/TLS error)")
            }
        }
    }
}
