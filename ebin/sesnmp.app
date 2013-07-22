{application,sesnmp,
             [{description,"Simpler SNMP Client Library"},
              {vsn,"2.0"},
              {modules,[sesnmp,sesnmp_app,sesnmp_client,sesnmp_client_sup,
                        sesnmp_misc,sesnmp_mpd,sesnmp_pdus,sesnmp_server,
                        sesnmp_sup,sesnmp_trapd,sesnmp_udp,snmp_mapping]},
              {registered,[]},
              {applications,[kernel,stdlib,sasl]},
              {env,[]},
              {mod,{sesnmp_app,[]}}]}.