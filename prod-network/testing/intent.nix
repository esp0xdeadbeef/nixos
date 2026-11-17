# Testing model intent (both sites).
#
# prod-network/testing is a self-contained, independent model. It is not a
# fork of prod-network/current and does not track it; the two directories have
# diverged deliberately (e.g. the cobalt VPN cores here use the ::/0 + NAT66
# translatedPrefixes form and include core-vpn-opal).
let
  traceroutePorts = builtins.genList (x: 33434 + x) 90;

  trafficTypes = [
    # The full outbound internet class: any protocol to anywhere outside the
    # site. This exists so a tenant's internet permission can name a real,
    # declared class (FS-180) instead of relying on the validator's synthetic
    # `"any"`. It is deliberately broad; narrower classes (dns, icmp,
    # traceroute, per-service ports) are declared separately and take their own
    # precedence.
    {
      name = "internet";
      match = [
        {
          proto = "any";
          family = "any";
        }
      ];
    }

    {
      name = "icmp";
      match = [
        {
          proto = "icmp";
          family = "ipv4";
        }
        {
          proto = "icmpv6";
          family = "ipv6";
        }
      ];
    }

    {
      name = "dns";
      match = [
        {
          proto = "udp";
          dports = [ 53 ];
          family = "any";
        }
        {
          proto = "tcp";
          dports = [ 53 ];
          family = "any";
        }
      ];
    }

    {
      name = "ssh";
      match = [
        {
          proto = "tcp";
          dports = [ 22 ];
          family = "any";
        }
      ];
    }

    {
      name = "web";
      match = [
        {
          proto = "tcp";
          dports = [
            80
            443
          ];
          family = "any";
        }
      ];
    }

    {
      name = "wireguard";
      match = [
        {
          proto = "udp";
          dports = [ 51820 ];
          family = "any";
        }
      ];
    }

    {
      name = "wireguard-1637";
      match = [
        {
          proto = "udp";
          dports = [ 1637 ];
          family = "any";
        }
      ];
    }

    {
      name = "bgp";
      match = [
        {
          proto = "tcp";
          dports = [ 179 ];
          family = "any";
        }
      ];
    }

    {
      name = "bfd";
      match = [
        {
          proto = "udp";
          dports = [ 3784 ];
          family = "any";
        }
      ];
    }

    {
      name = "nebula";
      match = [
        {
          proto = "udp";
          dports = [ 4242 ];
          family = "any";
        }
        {
          proto = "tcp";
          dports = [ 4242 ];
          family = "any";
        }
      ];
    }

    {
      name = "nebula-garnet";
      match = [
        {
          proto = "udp";
          dports = [ 4243 ];
          family = "any";
        }
        {
          proto = "tcp";
          dports = [ 4243 ];
          family = "any";
        }
      ];
    }

    {
      name = "tang";
      match = [
        {
          proto = "tcp";
          dports = [ 7500 ];
          family = "any";
        }
      ];
    }

    # Ollama inference API (FS-180: ports belong to the service, not the
    # relation).  Exposed cross-site over the garnet overlay to cobalt-svc.
    {
      name = "ollama";
      match = [
        {
          proto = "tcp";
          dports = [ 11434 ];
          family = "any";
        }
      ];
    }

    # Game servers exposed to the internet from the dmz plane (FS-180: the
    # ports belong to the service, not the relation).  Minecraft prod/test and
    # the Valheim connect port (2456; 2457/2458 are the query/steam ports the
    # server also binds).
    #
    # IPv4 only: the neon-dmz tenant declares no `routedPrefixes` runtime IPv6
    # allocation, so the dmz has no public IPv6 surface to ingress on.  Saying
    # `ipv4` here is the honest model; an `any` family would claim an IPv6
    # public ingress authority the dmz does not have (FS-310
    # PUBLIC_INGRESS_IPV6_AUTHORITY_MISSING).
    {
      name = "game-server";
      match = [
        {
          proto = "tcp";
          dports = [
            25565
            25566
          ];
          family = "ipv4";
        }
        {
          proto = "udp";
          dports = [
            2456
            2457
            2458
          ];
          family = "ipv4";
        }
      ];
    }

    {
      name = "traceroute";
      match = [
        {
          proto = "udp";
          dports = traceroutePorts;
          family = "any";
        }
      ];
    }
  ];

  # A tenant's outbound internet permission, as a bounded FS-180 tuple.
  #
  # This used to name no traffic class and no exit scope:
  #
  #   to = { kind = "external"; };   # no scope
  #   # no trafficType                  -> compiler fills in "any"
  #
  # `"any"` is a validator-level class the compiler synthesises, never a
  # declared traffic type, and the control-plane model drops a relation whose
  # class it cannot resolve to a match -- so every tenant got DNS (its own
  # explicit relation) and nothing else. That is why the IoT bench had no
  # internet while ping appeared to work over an unrelated Wi-Fi path.
  #
  # FS-180 requires the tuple to name the destination scope and the traffic
  # class, so name them: the `wan` exit scope and the `internet` class below.
  allowTenantToWan = tenant: priority:
    allowFromTo "allow-${tenant}-to-wan" priority (tenantRef tenant) coreScope "internet";

  # -------------------------------------------------------------------------
  # Relation shapes
  #
  # Almost every relation in the contract is the same fixed shape with only
  # the endpoints and the traffic class varying, so state the shape once here
  # and let the relation lists name only what actually differs. Each helper
  # expands to exactly the attribute set it replaces.
  # -------------------------------------------------------------------------

  allowFromTo = id: priority: from: to: trafficType: {
    inherit id priority from to trafficType;
    action = "allow";
    returnBehavior = "symmetric";
  };

  # A tenant account (the `from` side of most relations).
  tenantRef = name: {
    kind = "tenant";
    inherit name;
  };

  # A modeled service (the `to` side of most relations).
  serviceRef = name: {
    kind = "service";
    inherit name;
  };

  # The site's own WAN exit, named as a scope rather than by resource name.
  coreScope = {
    kind = "external";
    scope = "core";
  };

  # `allow-<tenant>-to-<service>`, the tenant-reaches-its-own-resolver shape.
  allowTenantToService = tenant: service: priority:
    allowFromTo "allow-${tenant}-to-${service}" priority
      (tenantRef tenant)
      (serviceRef service)
      "dns";

  # The denied counterpart of `allowFromTo`. The endpoints may be any scope,
  # so the id is always explicit.
  denyFromTo = id: priority: from: to: trafficType: {
    inherit id priority from to trafficType;
    action = "deny";
  };

  # One access resolver querying another resolver directly.
  allowResolverToResolver = from: to: priority:
    allowFromTo "allow-${from}-to-${to}" priority
      (serviceRef from)
      (serviceRef to)
      "dns";

  # An access resolver forwarding to the site's core recursive resolver.
  allowResolverToCoreDns = resolver: priority:
    allowFromTo "allow-${resolver}-to-core-dns" priority
      (serviceRef resolver)
      (serviceRef "core-dns")
      "dns";

  # Every tenant of a site reaching the site's Tang box. Relation ids drop the
  # site prefix (`allow-clients-to-tang`, not `allow-neon-clients-to-tang`), so
  # the short id name is derived from the tenant name here. The three probe
  # classes are emitted as three families over the same tenant list.
  allowTenantsToTang = { site, tenants, unlock }:
    let
      short = tenant: builtins.replaceStrings [ "${site}-" ] [ "" ] tenant;
      family = class: priority: suffix:
        map
          (tenant:
            allowFromTo "allow-${short tenant}-to-tang${suffix}" priority
              (tenantRef tenant)
              (tenantRef unlock)
              class)
          tenants;
    in
    family "tang" 85 "" ++ family "icmp" 84 "-icmp" ++ family "traceroute" 83 "-traceroute";

  # A public-ingress relation: the WAN surface binds ports on a service. Only
  # the target service, its traffic class, the target port, the address family
  # and the tuple list vary; the FS-210/FS-220/FS-230/FS-310 authority fields
  # are the same for every binding.
  #
  # One relation carries one `targetPort` (the CPM inherits it onto every
  # tuple), so a service reachable on several ports needs one binding per port.
  publicIngress = { id, priority, service, trafficType, targetPort, tuples, family ? null }:
    let
      ipv6 = family == "ipv6";
    in
    # No top-level `returnBehavior`: the return path is stated once, inside the
      # authority, as `stateful-return`.
    builtins.removeAttrs
      (allowFromTo id priority { kind = "external"; scope = "core"; } (serviceRef service) trafficType)
      [ "returnBehavior" ]
    // {
      publicIngressTupleAuthority = {
        sourceScope = "internet";
        publicSurface = "wan";
        targetService = service;
        targetEndpoint = service;
        inherit targetPort;
        returnBehavior = "stateful-return";
        # IPv4 traverses the site's single public address, so it is rewritten
        # (NAPT) and a hairpin/asymmetry statement is meaningful. IPv6 has no
        # translation surface: it keeps its source, states no translation
        # mode, and so carries neither hairpin nor asymmetricRouting.
        sourcePreservation = if ipv6 then "preserve-source" else "rewritten";
        translationMode = if ipv6 then "none" else "napt";
        inherit tuples;
      }
      // (if ipv6 then { inherit family; } else {
        hairpin = "not-modeled";
        asymmetricRouting = "not-allowed";
      });
    };

  # A tenant reaching the cross-site garnet overlay. The overlay is a one-way
  # path: replies come back over the same tunnel, not as a modeled reverse
  # relation, so the return behavior is not symmetric here. `shortName` is the
  # id form (`mgmt`, not `neon-mgmt`): relation ids drop the site prefix.
  allowTenantToGarnet = { tenant, shortName, priority }: {
    id = "allow-${shortName}-to-garnet";
    inherit priority;
    from = tenantRef tenant;
    to = garnetRef;
    trafficType = "any";
    action = "allow";
    returnBehavior = "one-way";
  };

  garnetRef = {
    kind = "external";
    name = "garnet";
  };

  # The garnet underlay's own path to the WAN.
  allowGarnetUnderlayToCore = priority: {
    id = "allow-garnet-underlay-to-core";
    inherit priority;
    from = garnetRef;
    to = coreScope;
    trafficType = "nebula-garnet";
    action = "allow";
    returnBehavior = "one-way";
  };

  # A resolver entry in recursiveDnsIntent. Every one of them is the same
  # contract: forward to a named upstream resolver on a named uplink and never
  # open a direct public fallback.
  recursiveDnsBinding = resolver: upstream: node: uplink: {
    requesterScope = serviceRef resolver;
    advertisedResolver = serviceRef resolver;
    resolverSource = "local-recursive";
    upstreamResolver = (serviceRef upstream) // { inherit node; };
    egressSurface = {
      kind = "external";
      uplinks = [ uplink ];
    };
    returnBehavior = "symmetric";
    allowedAddressFamilies = [
      "ipv4"
      "ipv6"
    ];
    directPublicFallback = false;
  };

  # The core resolver service declaration, shared by both sites.
  coreDnsService = {
    name = "core-dns";
    providerNode = "core";
    addressAuthority = "model-allocated-service-prefix";
    trafficType = "dns";
  };

  runtimeIpv6Prefix = tenant: slot: {
    allocation = "runtime";
    family = "ipv6";
    name = "${tenant}-public";
    delegatedPrefixLength = 48;
    perTenantPrefixLength = 64;
    inherit slot;
    sourceFile = "/run/secrets/subnet-ipv6-${tenant}";
  };

  # The `relation` a namespace-sharing grant carries: always a symmetric dns
  # allow between two access resolvers (FS-540).
  dnsSharingRelation = id: from: to: {
    inherit id;
    from = serviceRef from;
    to = serviceRef to;
    trafficType = "dns";
    returnBehavior = "symmetric";
  };

  # The namespace authority answers only for its own records and refuses the
  # rest, so a requester can never borrow its recursion (FS-560).
  refuseNonLocalProvider = source: {
    inherit source;
    action = "refuse_non_local";
  };

  # A modeled service and the endpoint(s) that provide it. Most services are
  # provided by the endpoint of the same name, so the provider list defaults to
  # exactly that.
  service = name: trafficType: providers: {
    inherit name providers trafficType;
  };

  # A host endpoint in a tenant. Ollama's address is inventory (FS-181) rather
  # than intent, so an endpoint may name only its IPv4 side and is then
  # declared by `hostEndpointV4`.
  hostEndpoint = name: tenant: ipv4: ipv6: {
    kind = "host";
    inherit name tenant ipv4;
  }
  // (if ipv6 == null then { } else { inherit ipv6; });

  # An access node attached to exactly one tenant.
  accessNode = { tenant, selects ? null }: {
    role = "access";
    attachments = [ (tenantRef tenant) ];
  }
  // (if selects == null then { } else { inherit selects; });

  # Every listed tenant takes its IPv6 address by SLAAC; the intent only names
  # which tenants are dual-stacked on the plane.
  slaacTenants = tenants: builtins.listToAttrs (map
    (name: {
      inherit name;
      value.mode = "slaac";
    })
    tenants);

  # A tenant's owned prefixes. Tenants that hand a runtime IPv6 block down to
  # the DHCPv6/RA path (the legacy vlan spaces) additionally list a
  # `routedPrefixes` allocation; the plane lanes do not and only state their
  # static prefixes.
  tenantPrefix = { name, dnsDomain, ipv4, ipv6, routedSlot ? null }: {
    kind = "tenant";
    inherit name dnsDomain ipv4 ipv6;
  }
  // (if routedSlot == null then { } else {
    routedPrefixes = [ (runtimeIpv6Prefix name routedSlot) ];
  });
in
{
  esp0xdeadbeef.neon = {
    pools = {
      p2p = {
        ipv4 = "10.10.0.0/24";
        ipv6 = "fd42:dead:beef:1000::/118";
      };

      loopback = {
        ipv4 = "10.19.0.0/24";
        ipv6 = "fd42:dead:beef:1900::/118";
      };

      overlay = {
        ipv4 = {
          prefix = "10.80.0.0/24";
          offsetStart = 10;
          perNodePrefixLength = 32;
        };
        ipv6 = {
          prefix = "fd42:dead:beef:80::/64";
          offsetStart = 10;
          perNodePrefixLength = 128;
        };
      };
    };

    ownership = {
      prefixes = [
        (tenantPrefix { name = "vlan2"; dnsDomain = "lan."; ipv4 = "192.168.1.0/24"; ipv6 = "fd42:1::/64"; routedSlot = 2; })
        (tenantPrefix { name = "vlan3"; dnsDomain = "lan."; ipv4 = "192.168.3.0/24"; ipv6 = "fd42:dead:beef:3::/64"; routedSlot = 3; })
        (tenantPrefix { name = "vlan7"; dnsDomain = "lan."; ipv4 = "192.168.2.0/24"; ipv6 = "fd42:dead:beef:7::/64"; routedSlot = 7; })
        (tenantPrefix { name = "vlan8"; dnsDomain = "lan."; ipv4 = "192.168.8.0/24"; ipv6 = "fd42:dead:beef:8::/64"; routedSlot = 8; })
        (tenantPrefix { name = "neon-mgmt"; dnsDomain = "mgmt.home.arpa."; ipv4 = "10.3.10.0/24"; ipv6 = "fd42:dead:beef:310::/64"; })
        (tenantPrefix { name = "neon-svc"; dnsDomain = "svc.home.arpa."; ipv4 = "10.3.20.0/24"; ipv6 = "fd42:dead:beef:320::/64"; })
        (tenantPrefix { name = "neon-clients"; dnsDomain = "clients.home.arpa."; ipv4 = "10.3.30.0/24"; ipv6 = "fd42:dead:beef:330::/64"; })
        (tenantPrefix { name = "neon-iot"; dnsDomain = "iot.home.arpa."; ipv4 = "10.3.50.0/24"; ipv6 = "fd42:dead:beef:350::/64"; })
        (tenantPrefix { name = "neon-iot-srv"; dnsDomain = "iot-srv.home.arpa."; ipv4 = "10.3.51.0/24"; ipv6 = "fd42:dead:beef:351::/64"; })
        (tenantPrefix { name = "neon-dmz"; dnsDomain = "dmz.home.arpa."; ipv4 = "10.3.60.0/24"; ipv6 = "fd42:dead:beef:360::/64"; })
        (tenantPrefix { name = "neon-unlock"; dnsDomain = "unlock.home.arpa."; ipv4 = "10.3.90.0/24"; ipv6 = "fd42:dead:beef:390::/64"; })
      ];

      endpoints = [
        (hostEndpoint "vlan2-dns" "vlan2" [ "192.168.1.1" ] [ "fd42:1::1" ])
        (hostEndpoint "vlan3-dns" "vlan3" [ "192.168.3.1" ] [ "fd42:dead:beef:3::1" ])
        (hostEndpoint "s-nebula-container" "vlan3" [ "192.168.3.10" ] [ "fd42:dead:beef:3::1337:dead:beef" ])
        (hostEndpoint "s-nebula-garnet" "vlan3" [ "192.168.3.12" ] [ "fd42:dead:beef:3::1337:e1ee:fbeb" ])
        # Ollama inference endpoint.  Intent names the host in its tenant;
        # the concrete 192.168.3.11 address is inventory (FS-181).  The
        # name must match the inventory endpoint key
        # (`s-llm-inference-container`) so the provider endpoint resolves.
        (hostEndpoint "s-llm-inference-container" "vlan3" [ "192.168.3.11" ] null)
        (hostEndpoint "vlan7-dns" "vlan7" [ "192.168.2.1" ] [ "fd42:dead:beef:7::1" ])
        (hostEndpoint "vlan8-dns" "vlan8" [ "192.168.8.1" ] [ "fd42:dead:beef:8::1" ])
        (hostEndpoint "neon-mgmt-dns" "neon-mgmt" [ "10.3.10.1" ] null)
        (hostEndpoint "neon-svc-dns" "neon-svc" [ "10.3.20.1" ] null)
        (hostEndpoint "neon-clients-dns" "neon-clients" [ "10.3.30.1" ] null)
        (hostEndpoint "neon-iot-dns" "neon-iot" [ "10.3.50.1" ] null)
        (hostEndpoint "neon-iot-srv-dns" "neon-iot-srv" [ "10.3.51.1" ] null)
        (hostEndpoint "neon-dmz-dns" "neon-dmz" [ "10.3.60.1" ] null)
        (hostEndpoint "s-gameserver" "neon-dmz" [ "10.3.60.10" ] null)
        (hostEndpoint "neon-unlock-dns" "neon-unlock" [ "10.3.90.1" ] null)
        (hostEndpoint "neon-tang" "neon-unlock" [ "10.3.90.10" ] null)
      ];
    };

    hostManagement = {
      required = true;
      interface = "vlan2";
      purpose = "hardware-management";
    };

    communicationContract = {
      inherit trafficTypes;
      services = [
        (service "vlan2-dns" "dns" [ "vlan2-dns" ])
        (service "vlan3-dns" "dns" [ "vlan3-dns" ])
        (service "vlan7-dns" "dns" [ "vlan7-dns" ])
        (service "vlan8-dns" "dns" [ "vlan8-dns" ])
        (service "s-nebula-container" "nebula" [ "s-nebula-container" ])
        (service "s-nebula-container-icmp" "icmp" [ "s-nebula-container" ])
        (service "s-nebula-garnet" "nebula-garnet" [ "s-nebula-garnet" ])
        # FS-190/FS-200: Ollama is a cross-site shared service in the vlan3
        # access space.  The service carries its own port via the `ollama`
        # traffic type; the relation only states who may reach it.  It is
        # served by the s-llm-inference endpoint and is reachable from
        # cobalt-svc over the garnet overlay (FS-460).
        {
          name = "s-llm-inference";
          providers = [ "s-llm-inference-container" ];
          trafficType = "ollama";
          servicePolicy = {
            requesterScopes = [{ kind = "tenant"; name = "cobalt-svc"; }];
            responderScope = { kind = "host"; name = "s-llm-inference-container"; tenant = "vlan3"; };
            serviceClass = "inference-api";
            discovery = {
              protocol = "none";
              direction = "none";
              advertisedServices = [ ];
            };
            payload = {
              protocol = "ollama";
              ports = [ 11434 ];
              direction = "requester-to-responder";
              returnBehavior = "established-only";
            };
            management = {
              allowed = false;
              boundary = "inference-host-local-only";
            };
            reverseInitiation = {
              allowed = false;
              boundary = "no-inference-initiated-client-paths";
            };
            deniedPaths = [
              {
                from = { kind = "tenant"; name = "vlan2"; };
                to = { kind = "service"; name = "s-llm-inference"; };
                reason = "vlan2-has-no-modeled-inference-relation";
                negativeProbe = "vlan2-to-llm-inference-tcp11434";
              }
            ];
            exposureClass = "cross-site";
            authenticationBoundary = "ollama-api-unauthenticated";
            cloudDependency = "none";
          };
        }
        (service "vlan2-gateway-icmp" "icmp" [ "vlan2-dns" ])
        (service "mgmt-dns" "dns" [ "neon-mgmt-dns" ])
        (service "svc-dns" "dns" [ "neon-svc-dns" ])
        (service "clients-dns" "dns" [ "neon-clients-dns" ])
        (service "iot-dns" "dns" [ "neon-iot-dns" ])
        (service "iot-srv-dns" "dns" [ "neon-iot-srv-dns" ])
        (service "dmz-dns" "dns" [ "neon-dmz-dns" ])
        (service "unlock-dns" "dns" [ "neon-unlock-dns" ])
        (service "tang" "tang" [ "neon-tang" ])
        # FS-190/FS-200: publicly-exposed game servers in the dmz access space.
        # The service carries its own ports via the `game-server` traffic type;
        # the public-ingress relations below bind who may reach it.  The
        # exposure class is public-ingress and the authentication boundary is
        # the game protocol itself.
        {
          name = "s-gameserver";
          providers = [ "s-gameserver" ];
          trafficType = "game-server";
          servicePolicy = {
            requesterScopes = [{ kind = "external"; scope = "core"; }];
            responderScope = { kind = "host"; name = "s-gameserver"; tenant = "neon-dmz"; };
            serviceClass = "game-server";
            discovery = {
              protocol = "none";
              direction = "none";
              advertisedServices = [ ];
            };
            payload = {
              protocol = "game-server";
              ports = [
                2456
                2457
                2458
                25565
                25566
              ];
              direction = "requester-to-responder";
              returnBehavior = "established-only";
            };
            management = {
              allowed = false;
              boundary = "gameserver-host-local-only";
            };
            reverseInitiation = {
              allowed = false;
              boundary = "no-gameserver-initiated-client-paths";
            };
            deniedPaths = [
              {
                from = { kind = "tenant"; name = "neon-clients"; };
                to = { kind = "service"; name = "s-gameserver"; };
                reason = "clients-reach-games-only-through-the-lan-path";
                negativeProbe = "neon-clients-to-s-gameserver-public-tuples";
              }
            ];
            exposureClass = "public-ingress";
            authenticationBoundary = "game-protocol-native";
            cloudDependency = "none";
          };
        }
      ];
      relations = builtins.concatMap (r: if builtins.isList r then r else [ r ]) [
        (allowTenantToService "vlan2" "vlan2-dns" 80)
        (allowTenantToService "vlan7" "vlan7-dns" 81)
        (allowTenantToService "vlan3" "vlan3-dns" 82)
        (allowTenantToService "vlan8" "vlan8-dns" 86)
        {
          # VLAN 2's resolver may query only VLAN 3's DNS service for the
          # shared lan. namespace. The resolver runtime narrows this further to
          # that namespace, and VLAN 3 serves this source with refuse_non_local
          # so VLAN 2 cannot borrow VLAN 3's recursive path to core/the
          # Internet. VLAN 3 owns the lan. records (192.168.3.x endpoints), so
          # it is the namespace authority; VLAN 2 resolves them through the
          # canonical staged path rather than holding a copy.
          id = "allow-vlan2-dns-to-vlan3-dns";
          priority = 79;
          from = {
            kind = "service";
            name = "vlan2-dns";
          };
          to = {
            kind = "service";
            name = "vlan3-dns";
          };
          trafficType = "dns";
          action = "allow";
          returnBehavior = "symmetric";
        }
        (allowFromTo "allow-vlan2-to-s-nebula-container-icmp" 83 (tenantRef "vlan2") (serviceRef "s-nebula-container-icmp") "icmp")
        (allowFromTo "allow-vlan2-to-vlan2-gateway-icmp" 82 (tenantRef "vlan2") (serviceRef "vlan2-gateway-icmp") "icmp")
        (denyFromTo "deny-vlan3-to-vlan2" 84 (tenantRef "vlan3") (tenantRef "vlan2") "any")
        (allowFromTo "allow-vlan2-to-vlan3" 85 (tenantRef "vlan2") (tenantRef "vlan3") "any")
        (publicIngress {
          id = "allow-wan-to-s-nebula-container";
          priority = 95;
          service = "s-nebula-container";
          trafficType = "nebula";
          targetPort = 4242;
          tuples = [
            {
              protocol = "udp";
              publicPort = 4242;
            }
            {
              protocol = "tcp";
              publicPort = 4242;
            }
          ];
        })
        (publicIngress {
          id = "allow-wan-to-s-nebula-container-ipv6";
          priority = 95;
          service = "s-nebula-container";
          trafficType = "nebula";
          targetPort = 4242;
          family = "ipv6";
          tuples = [
            {
              protocol = "udp";
              publicPort = 4242;
            }
            {
              protocol = "tcp";
              publicPort = 4242;
            }
          ];
        })
        # FS-210/FS-230: public ingress for the neon dmz game servers.  The
        # IPv4 path is NAPT (the site has one public IPv4 surface).  FS-220
        # uniqueness holds because no other binding claims these ports on the
        # wan surface.
        #
        # One relation per public port: the CPM derives a single
        # `targetPort` from the relation and applies it to every tuple
        # (`tupleRecords` in cpm/firewall-intent/public-ingress.nix `inherit
        # targetPort`), so a multi-tuple relation would DNAT every public port
        # to the same target port.  The game server's public and target ports
        # are identical, which only a per-port relation can express today.
        #
        # IPv6 is intentionally not modeled: public IPv6 ingress needs a
        # `routedPrefixes` runtime allocation on the tenant and neon-dmz has
        # none (only vlan2/3/7/8 do), so the traffic type is declared ipv4 and
        # no IPv6 ingress authority is claimed (FS-310
        # PUBLIC_INGRESS_IPV6_AUTHORITY_MISSING).
        (publicIngress {
          id = "allow-wan-to-s-gameserver-mc-prod";
          priority = 90;
          service = "s-gameserver";
          trafficType = "game-server";
          targetPort = 25565;
          tuples = [
            {
              protocol = "tcp";
              publicPort = 25565;
              targetPort = 25565;
            }
          ];
        })
        (publicIngress {
          id = "allow-wan-to-s-gameserver-mc-test";
          priority = 91;
          service = "s-gameserver";
          trafficType = "game-server";
          targetPort = 25566;
          tuples = [
            {
              protocol = "tcp";
              publicPort = 25566;
              targetPort = 25566;
            }
          ];
        })
        # Valheim: 2456 is the connect port; 2457/2458 are the query/steam
        # ports the server also binds.  Each needs its own relation for the
        # same single-targetPort reason as above.
        (publicIngress {
          id = "allow-wan-to-s-gameserver-valheim";
          priority = 92;
          service = "s-gameserver";
          trafficType = "game-server";
          targetPort = 2456;
          tuples = [
            {
              protocol = "udp";
              publicPort = 2456;
              targetPort = 2456;
            }
          ];
        })
        (publicIngress {
          id = "allow-wan-to-s-gameserver-valheim-query";
          priority = 93;
          service = "s-gameserver";
          trafficType = "game-server";
          targetPort = 2457;
          tuples = [
            {
              protocol = "udp";
              publicPort = 2457;
              targetPort = 2457;
            }
          ];
        })
        (publicIngress {
          id = "allow-wan-to-s-gameserver-valheim-steam";
          priority = 94;
          service = "s-gameserver";
          trafficType = "game-server";
          targetPort = 2458;
          tuples = [
            {
              protocol = "udp";
              publicPort = 2458;
              targetPort = 2458;
            }
          ];
        })
        (publicIngress {
          id = "allow-wan-to-s-nebula-garnet";
          priority = 96;
          service = "s-nebula-garnet";
          trafficType = "nebula-garnet";
          targetPort = 4243;
          tuples = [
            {
              protocol = "udp";
              publicPort = 4243;
            }
            {
              protocol = "tcp";
              publicPort = 4243;
            }
          ];
        })
        (publicIngress {
          id = "allow-wan-to-s-nebula-garnet-ipv6";
          priority = 96;
          service = "s-nebula-garnet";
          trafficType = "nebula-garnet";
          targetPort = 4243;
          family = "ipv6";
          tuples = [
            {
              protocol = "udp";
              publicPort = 4243;
            }
            {
              protocol = "tcp";
              publicPort = 4243;
            }
          ];
        })
        (allowTenantToWan "vlan2" 100)
        (allowTenantToWan "vlan7" 110)
        (allowTenantToWan "vlan8" 120)
        (allowResolverToResolver "clients-dns" "dmz-dns" 78)
        (allowResolverToResolver "dmz-dns" "clients-dns" 79)
        (allowResolverToResolver "clients-dns" "unlock-dns" 81)
        (allowFromTo "allow-clients-to-clients-dns" 80 (tenantRef "neon-clients") (serviceRef "clients-dns") "dns")
        (allowFromTo "allow-svc-to-svc-dns" 81 (tenantRef "neon-svc") (serviceRef "svc-dns") "dns")
        (allowFromTo "allow-dmz-to-dmz-dns" 82 (tenantRef "neon-dmz") (serviceRef "dmz-dns") "dns")
        (denyFromTo "deny-dmz-to-clients" 84 (tenantRef "neon-dmz") (tenantRef "neon-clients") "any")
        (allowFromTo "allow-clients-to-dmz" 85 (tenantRef "neon-clients") (tenantRef "neon-dmz") "any")
        (allowFromTo "allow-iot-to-iot-dns" 86 (tenantRef "neon-iot") (serviceRef "iot-dns") "dns")
        (allowFromTo "allow-iot-srv-to-iot-srv-dns" 87 (tenantRef "neon-iot-srv") (serviceRef "iot-srv-dns") "dns")
        # The unlock tenant reaches the Tang service it hosts directly.
        (allowFromTo "allow-unlock-to-tang" 85 (tenantRef "neon-unlock") (serviceRef "tang") "tang")

        # Tang: every access tenant of this site reaches the Tang box over the
        # plain, icmp and traceroute classes.
        (allowTenantsToTang {
          site = "neon";
          tenants = [ "neon-clients" "neon-svc" "neon-iot" "neon-iot-srv" "neon-dmz" "neon-mgmt" ];
          unlock = "neon-unlock";
        })

        (allowFromTo "allow-mgmt-to-mgmt-dns" 88 (tenantRef "neon-mgmt") (serviceRef "mgmt-dns") "dns")
        (allowTenantToWan "neon-clients" 100)
        (allowTenantToWan "neon-svc" 110)
        (allowTenantToWan "neon-iot" 120)
        (allowTenantToWan "neon-iot-srv" 130)
        (allowTenantToWan "neon-mgmt" 140)
        (allowTenantToGarnet { tenant = "neon-mgmt"; shortName = "mgmt"; priority = 150; })
        (allowTenantToGarnet { tenant = "neon-svc"; shortName = "svc"; priority = 151; })
        (allowTenantToGarnet { tenant = "neon-dmz"; shortName = "dmz"; priority = 152; })
        # The garnet underlay tenant reaches the ISP itself, not just `wan`.
        {
          id = "allow-iot-srv-nebula-garnet-underlay-to-isp";
          priority = 153;
          from = tenantRef "neon-iot-srv";
          to = { kind = "external"; };
          trafficType = "nebula-garnet";
          action = "allow";
          returnBehavior = "one-way";
        }
        (allowGarnetUnderlayToCore 154)
        # FS-460: cobalt-svc reaches the vlan3 Ollama service over the garnet
        # overlay.  The remote side of the path is the overlay ingress facing
        # the s-llm-inference service; the payload port lives on the service
        # (FS-180).
        {
          id = "allow-garnet-to-s-llm-inference";
          priority = 155;
          from = {
            kind = "external";
            name = "garnet";
          };
          to = {
            kind = "service";
            name = "s-llm-inference";
          };
          trafficType = "ollama";
          action = "allow";
          returnBehavior = "symmetric";
        }
      ];
    };

    # FS-540 recursive DNS contract. Every access resolver (legacy vlan2/7/8
    # and the new plane lanes) forwards to core-dns, and core-dns is the only
    # modeled DNS egress surface to the WAN. Direct service-to-WAN DNS allows
    # are intentionally absent from the communication contract: alongside
    # allow-core-dns-to-wan they describe a second egress path for the same
    # resolver, and the forwarding model's transitive egress closure cannot
    # normalize that dual path (it renders a self-referential policy-container
    # config). The inventory pins each access Unbound resolver to core-dns.
    recursiveDnsIntent = {
      services = [ coreDnsService ];

      relations = [
        (allowFromTo "allow-core-dns-to-wan" 90 (serviceRef "core-dns") coreScope "dns")
        # VLAN 2 clients may query the internal core resolver directly. This
        # is a normal supported path: core remains bound only to its
        # upstream-selector-facing service surface, and VLAN 3 deliberately
        # has no equivalent relation.
        (allowFromTo "allow-vlan2-to-core-dns" 87 (tenantRef "vlan2") (serviceRef "core-dns") "dns")
        (allowResolverToCoreDns "vlan2-dns" 88)
        (allowResolverToCoreDns "vlan7-dns" 89)
        (denyFromTo "deny-vlan2-dns-to-wan" 92 (serviceRef "vlan2-dns") coreScope "dns")
        (denyFromTo "deny-vlan7-dns-to-wan" 93 (serviceRef "vlan7-dns") coreScope "dns")
        (allowResolverToCoreDns "vlan8-dns" 94)
        (allowFromTo "allow-clients-to-core-dns" 87 (tenantRef "neon-clients") (serviceRef "core-dns") "dns")
        (allowResolverToCoreDns "clients-dns" 88)
        (allowFromTo "allow-mgmt-to-core-dns" 89 (tenantRef "neon-mgmt") (serviceRef "core-dns") "dns")
        (allowResolverToCoreDns "mgmt-dns" 90)
        (allowResolverToCoreDns "svc-dns" 89)
        (denyFromTo "deny-clients-dns-to-wan" 92 (serviceRef "clients-dns") coreScope "dns")
        (denyFromTo "deny-svc-dns-to-wan" 93 (serviceRef "svc-dns") coreScope "dns")
        (allowResolverToCoreDns "iot-dns" 94)
        (allowResolverToCoreDns "iot-srv-dns" 95)
      ];

      bindings = [
        (recursiveDnsBinding "vlan2-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "vlan7-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "vlan8-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "clients-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "svc-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "iot-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "iot-srv-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "mgmt-dns" "core-dns" "core" "wan")
      ];
    };

    # Desired local namespace-sharing contract. vlan3 owns its static lan.
    # records (s-nebula-container etc.) and acts as the namespace authority;
    # vlan2 is the requester and reaches those records through the modeled
    # forward zone and the canonical staged path
    # (access-vlan2 -> downstream-selector -> access-vlan3). Namespace
    # authority is never transferred by a sharing relationship: the authority
    # answers authoritatively only for its own records (FS-560), and the
    # requester resolves the rest through the forward relation (FS-540).
    localDnsSharingIntent = [
      {
        namespace = "lan.";
        authority = {
          service = "vlan3-dns";
          records = [
            "vlan3-static-local-data"
          ];
        };
        requester = {
          service = "vlan2-dns";
          allowedNamespaces = [
            "lan."
            "3.168.192.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = dnsSharingRelation "allow-vlan2-dns-to-vlan3-dns" "vlan2-dns" "vlan3-dns";
        providerPolicy = refuseNonLocalProvider "vlan2-dns";
        lateralPolicy = {
          source = "vlan3";
          target = "vlan2-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
      {
        namespace = "home.arpa.";
        authority = {
          service = "clients-dns";
          records = [
            "clients-kea-local-data"
            "dmz-static-local-data"
          ];
        };
        requester = {
          service = "dmz-dns";
          allowedNamespaces = [
            "home.arpa."
            "30.3.10.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = dnsSharingRelation "allow-dmz-dns-to-clients-dns" "dmz-dns" "clients-dns";
        providerPolicy = refuseNonLocalProvider "dmz-dns";
        lateralPolicy = {
          source = "neon-clients";
          target = "dmz-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
      {
        namespace = "home.arpa.";
        authority = {
          service = "unlock-dns";
          records = [
            "unlock-static-local-data"
          ];
        };
        requester = {
          service = "clients-dns";
          allowedNamespaces = [
            "unlock.home.arpa."
            "90.3.10.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = dnsSharingRelation "allow-clients-dns-to-unlock-dns" "clients-dns" "unlock-dns";
        providerPolicy = refuseNonLocalProvider "clients-dns";
        lateralPolicy = {
          source = "neon-unlock";
          target = "clients-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
    ];

    ipv6 = {
      pd = {
        uplink = "wan";
        delegatedPrefixLength = 48;
        perTenantPrefixLength = 64;
      };
      tenants = slaacTenants [ "vlan2" "vlan3" "vlan7" "vlan8" "neon-mgmt" "neon-svc" "neon-clients" "neon-iot" "neon-iot-srv" "neon-dmz" "neon-unlock" ];
    };

    topology = {
      nodes = {
        core = {
          role = "core";

          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
              egress.ipv4.translation = {
                mode = "nat44";
              };
            };
          };
        };

        # Service-only peer overlay (NAS, printer, future vlan10+ services).
        # It selects the peer site's service scopes, which own their prefixes
        # (FS-322), and offers no default: an egress (default offers 0.0.0.0/0
        # and ::/0) is not modeled here.
        core-vpn-garnet-neon = {
          role = "core";

          selects = [
            "access-svc"
            "access-dmz"
            # FS-460: the garnet overlay also carries cobalt-svc -> ollama in
            # the vlan3 access space, so the overlay core must select it.
            "access-vlan3"
          ];
        };

        upstream-selector = {
          role = "upstream-selector";
        };

        policy = {
          role = "policy";
        };

        downstream-selector = {
          role = "downstream-selector";
        };

        access-vlan2 = accessNode { tenant = "vlan2"; selects = [ "wan" ]; };

        access-vlan3 = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "vlan3";
            }
          ];
          # FS-322: vlan3 owns 192.168.3.0/24; it offers that prefix so the
          # garnet overlay peer site can route toward it.  The offer is
          # reachability only; payload still needs the s-llm-inference
          # relation (FS-170/FS-180).
          offers = [
            "192.168.3.0/24"
          ];
        };

        access-vlan7 = accessNode { tenant = "vlan7"; selects = [ "wan" ]; };

        access-vlan8 = accessNode { tenant = "vlan8"; selects = [ "wan" ]; };
        access-mgmt = accessNode { tenant = "neon-mgmt"; selects = [ "wan" ]; };
        access-svc = accessNode { tenant = "neon-svc"; selects = [ "wan" ]; };
        access-clients = accessNode { tenant = "neon-clients"; selects = [ "wan" ]; };
        access-iot = accessNode { tenant = "neon-iot"; selects = [ "wan" ]; };
        access-iot-srv = accessNode { tenant = "neon-iot-srv"; selects = [ "wan" ]; };
        access-dmz = accessNode { tenant = "neon-dmz"; };
        access-unlock = accessNode { tenant = "neon-unlock"; };
      };

      links = [
        [ "core" "upstream-selector" ]
        [ "core-vpn-garnet-neon" "upstream-selector" ]
        [ "upstream-selector" "policy" ]
        [ "policy" "downstream-selector" ]
        [ "downstream-selector" "access-vlan2" ]
        [ "downstream-selector" "access-vlan3" ]
        [ "downstream-selector" "access-vlan7" ]
        [ "downstream-selector" "access-vlan8" ]
        [ "downstream-selector" "access-mgmt" ]
        [ "downstream-selector" "access-svc" ]
        [ "downstream-selector" "access-clients" ]
        [ "downstream-selector" "access-iot" ]
        [ "downstream-selector" "access-iot-srv" ]
        [ "downstream-selector" "access-dmz" ]
        [ "downstream-selector" "access-unlock" ]
      ];
    };

    transport = {
      overlays = [
        {
          name = "garnet";
          terminateOn = "core-vpn-garnet-neon";
          peerSite = "esp0xdeadbeef.cobalt";
          mustTraverse = [ "policy" ];
          underlayAccess = {
            kind = "tenant";
            name = "neon-iot-srv";
          };
          # URS (Reachability, Routing, and Overlays): overlay transport models
          # endpoint identity, permitted peers, and imported/exported prefixes.
          # Both address families are explicit.  exported = prefixes this site
          # offers on the overlay (the offering scopes own them, FS-322);
          # imported = the peer's prefixes, which this site routes through the
          # overlay so a single-site compile is not silently empty.  The peer's
          # garnet participant address is the next hop for the imported prefixes
          # (a peer site is not compiled in this site's pass, so it is modeled
          # here as the overlay's endpoint identity).
          peerNodes = {
            "esp0xdeadbeef.cobalt" = {
              addr4 = "10.80.0.2/24";
              addr6 = "fd42:dead:beef:80::2/64";
            };
          };
          prefixes = {
            exported = {
              ipv4 = [ "192.168.3.0/24" ];
              ipv6 = [ "fd42:dead:beef:3::/64" ];
            };
            imported = {
              ipv4 = [ "10.2.20.0/24" ];
              ipv6 = [ "fd42:dead:beef:220::/64" ];
            };
          };
        }
      ];
    };
  };

  esp0xdeadbeef.cobalt = {
    pools = {
      p2p = {
        ipv4 = "10.1.0.0/24";
        ipv6 = "fd42:dead:beef:2000::/118";
      };

      loopback = {
        ipv4 = "10.1.1.0/24";
        ipv6 = "fd42:dead:beef:2900::/118";
      };

      overlay = {
        ipv4 = {
          prefix = "10.80.0.0/24";
          offsetStart = 10;
          perNodePrefixLength = 32;
        };
        ipv6 = {
          prefix = "fd42:dead:beef:80::/64";
          offsetStart = 10;
          perNodePrefixLength = 128;
        };
      };
    };

    ownership = {
      prefixes = [
        (tenantPrefix { name = "cobalt-svc"; dnsDomain = "svc.home.arpa."; ipv4 = "10.2.20.0/24"; ipv6 = "fd42:dead:beef:220::/64"; })
        (tenantPrefix { name = "cobalt-clients"; dnsDomain = "clients.home.arpa."; ipv4 = "10.2.30.0/24"; ipv6 = "fd42:dead:beef:230::/64"; })
        (tenantPrefix { name = "cobalt-iot"; dnsDomain = "iot.home.arpa."; ipv4 = "10.2.50.0/24"; ipv6 = "fd42:dead:beef:250::/64"; })
        (tenantPrefix { name = "cobalt-iot-srv"; dnsDomain = "iot-srv.home.arpa."; ipv4 = "10.2.51.0/24"; ipv6 = "fd42:dead:beef:251::/64"; })
        (tenantPrefix { name = "cobalt-dmz"; dnsDomain = "dmz.home.arpa."; ipv4 = "10.2.60.0/24"; ipv6 = "fd42:dead:beef:260::/64"; })
        (tenantPrefix { name = "cobalt-clients-vpn"; dnsDomain = "clients-vpn.home.arpa."; ipv4 = "10.2.31.0/24"; ipv6 = "fd42:dead:beef:231::/64"; })
        (tenantPrefix { name = "cobalt-unlock"; dnsDomain = "unlock.home.arpa."; ipv4 = "10.2.90.0/24"; ipv6 = "fd42:dead:beef:290::/64"; })
        (tenantPrefix { name = "cobalt-mgmt"; dnsDomain = "mgmt.home.arpa."; ipv4 = "10.2.10.0/24"; ipv6 = "fd42:dead:beef:210::/64"; })
      ];

      endpoints = [
        (hostEndpoint "cobalt-svc-dns" "cobalt-svc" [ "10.2.20.1" ] null)
        (hostEndpoint "cobalt-clients-dns" "cobalt-clients" [ "10.2.30.1" ] null)
        (hostEndpoint "cobalt-iot-dns" "cobalt-iot" [ "10.2.50.1" ] null)
        (hostEndpoint "cobalt-iot-srv-dns" "cobalt-iot-srv" [ "10.2.51.1" ] null)
        (hostEndpoint "cobalt-dmz-dns" "cobalt-dmz" [ "10.2.60.1" ] null)
        (hostEndpoint "cobalt-clients-vpn-dns" "cobalt-clients-vpn" [ "10.2.31.1" ] null)
        (hostEndpoint "cobalt-tang" "cobalt-unlock" [ "10.2.90.10" ] null)
        (hostEndpoint "cobalt-mgmt-dns" "cobalt-mgmt" [ "10.2.10.1" ] null)
        (hostEndpoint "cobalt-unlock-dns" "cobalt-unlock" [ "10.2.90.1" ] null)
        (hostEndpoint "s-nebula-cobalt-lighthouse" "cobalt-svc" [ "10.2.20.2" ] null)
      ];
    };

    hostManagement = {
      required = true;
      interface = "vlan10";
      purpose = "hardware-management";
    };

    communicationContract = {
      trafficTypes =
        trafficTypes
        ++ [
          {
            name = "nebula-ipv4";
            match = [
              {
                proto = "udp";
                dports = [ 4242 ];
                family = "ipv4";
              }
              {
                proto = "tcp";
                dports = [ 4242 ];
                family = "ipv4";
              }
            ];
          }
        ];
      services = [
        (service "svc-dns" "dns" [ "cobalt-svc-dns" ])
        (service "clients-dns" "dns" [ "cobalt-clients-dns" ])
        (service "iot-dns" "dns" [ "cobalt-iot-dns" ])
        (service "iot-srv-dns" "dns" [ "cobalt-iot-srv-dns" ])
        (service "dmz-dns" "dns" [ "cobalt-dmz-dns" ])
        (service "clients-vpn-dns" "dns" [ "cobalt-clients-vpn-dns" ])
        (service "tang" "tang" [ "cobalt-tang" ])
        (service "unlock-dns" "dns" [ "cobalt-unlock-dns" ])
        (service "mgmt-dns" "dns" [ "cobalt-mgmt-dns" ])
        (service "s-nebula-cobalt-lighthouse" "nebula-ipv4" [ "s-nebula-cobalt-lighthouse" ])
      ];

      relations = builtins.concatMap (r: if builtins.isList r then r else [ r ]) [
        (allowResolverToResolver "clients-dns" "dmz-dns" 78)
        (allowResolverToResolver "dmz-dns" "clients-dns" 79)
        (allowResolverToResolver "clients-dns" "unlock-dns" 81)
        (allowFromTo "allow-clients-to-clients-dns" 80 (tenantRef "cobalt-clients") (serviceRef "clients-dns") "dns")
        (allowFromTo "allow-svc-to-svc-dns" 81 (tenantRef "cobalt-svc") (serviceRef "svc-dns") "dns")
        (allowFromTo "allow-dmz-to-dmz-dns" 82 (tenantRef "cobalt-dmz") (serviceRef "dmz-dns") "dns")
        {
          id = "deny-dmz-to-clients";
          priority = 84;
          from = {
            kind = "tenant";
            name = "cobalt-dmz";
          };
          to = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-clients-to-dmz";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-clients";
          };
          to = {
            kind = "tenant";
            name = "cobalt-dmz";
          };
          trafficType = "any";
          action = "allow";
          returnBehavior = "symmetric";
        }
        (allowFromTo "allow-iot-to-iot-dns" 86 (tenantRef "cobalt-iot") (serviceRef "iot-dns") "dns")
        (allowFromTo "allow-iot-srv-to-iot-srv-dns" 87 (tenantRef "cobalt-iot-srv") (serviceRef "iot-srv-dns") "dns")
        (allowFromTo "allow-clients-vpn-to-clients-vpn-dns" 87 (tenantRef "cobalt-clients-vpn") (serviceRef "clients-vpn-dns") "dns")
        # The unlock tenant reaches the Tang service it hosts directly.
        (allowFromTo "allow-unlock-to-tang" 85 (tenantRef "cobalt-unlock") (serviceRef "tang") "tang")

        # Tang: every access tenant of this site reaches the Tang box over the
        # plain, icmp and traceroute classes.
        (allowTenantsToTang {
          site = "cobalt";
          tenants = [ "cobalt-clients" "cobalt-svc" "cobalt-iot" "cobalt-iot-srv" "cobalt-dmz" "cobalt-clients-vpn" "cobalt-mgmt" ];
          unlock = "cobalt-unlock";
        })
        (allowFromTo "allow-mgmt-to-mgmt-dns" 88 (tenantRef "cobalt-mgmt") (serviceRef "mgmt-dns") "dns")
        (allowFromTo "allow-clients-dns-to-wan" 90 (serviceRef "clients-dns") coreScope "dns")
        (allowFromTo "allow-svc-dns-to-wan" 91 (serviceRef "svc-dns") coreScope "dns")
        (publicIngress {
          id = "allow-wan-to-s-nebula-cobalt-lighthouse";
          priority = 95;
          service = "s-nebula-cobalt-lighthouse";
          trafficType = "nebula-ipv4";
          targetPort = 4242;
          tuples = [
            {
              protocol = "udp";
              publicPort = 4242;
            }
            {
              protocol = "tcp";
              publicPort = 4242;
            }
          ];
        })
        (allowFromTo "allow-iot-dns-to-wan" 93 (serviceRef "iot-dns") coreScope "dns")
        (allowFromTo "allow-iot-srv-dns-to-wan" 94 (serviceRef "iot-srv-dns") coreScope "dns")
        (allowFromTo "allow-mgmt-dns-to-wan" 95 (serviceRef "mgmt-dns") coreScope "dns")
        (allowTenantToWan "cobalt-clients" 100)
        (allowTenantToWan "cobalt-svc" 110)
        (allowTenantToWan "cobalt-iot" 120)
        (allowTenantToWan "cobalt-mgmt" 140)
        # cobalt-iot-srv is not an ordinary egress tenant: it is the
        # underlayAccess carrier for the onyx/opal VPN overlays. Its WAN need
        # is exactly the WireGuard transport (udp/1637), so it names that class
        # instead of the blanket `internet` one. The overlay validator
        # (E_OVERLAY_UNDERLAY_ACCESS_WAN_EGRESS_REQUIRED) requires the underlay
        # tenant to have an allow to the underlay's target external; naming the
        # real class states that intent precisely rather than widening it.
        # The garnet overlay is carried by the same underlay tenant, but its
        # transport class is nebula-garnet (udp/tcp 4243), not the WireGuard
        # class above. Without this the underlay could only reach garnet
        # *through* the garnet overlay -- circular, which is exactly what
        # E_OVERLAY_UNDERLAY_ACCESS_WAN_EGRESS_REQUIRED rejects, and what left
        # iot-srv (the VPN underlay gateway) with no egress at all.
        {
          id = "allow-cobalt-iot-srv-to-wan-nebula-garnet";
          priority = 131;
          from = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
          to = { kind = "external"; scope = "core"; };
          trafficType = "nebula-garnet";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-cobalt-iot-srv-to-wan";
          priority = 130;
          from = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
          to = { kind = "external"; scope = "core"; };
          trafficType = "wireguard-1637";
          action = "allow";
          returnBehavior = "symmetric";
        }
        (allowGarnetUnderlayToCore 154)
        {
          id = "allow-clients-vpn-to-vpn-uplinks";
          priority = 85;
          from = {
            kind = "tenant";
            name = "cobalt-clients-vpn";
          };
          to = { kind = "external"; };
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-onyx-uplink-to-wan";
          priority = 140;
          from = {
            kind = "external";
            name = "onyx";
          };
          to = { kind = "external"; scope = "core"; };
          trafficType = "wireguard-1637";
          action = "allow";
          returnBehavior = "symmetric";
        }
        {
          id = "allow-opal-uplink-to-wan";
          priority = 141;
          from = {
            kind = "external";
            name = "opal";
          };
          to = { kind = "external"; scope = "core"; };
          trafficType = "wireguard-1637";
          action = "allow";
          returnBehavior = "symmetric";
        }
      ];
    };

    recursiveDnsIntent = {
      services = [
        coreDnsService
        {
          name = "onyx-dns";
          providerNode = "core-vpn-onyx";
          addressAuthority = "model-allocated-service-prefix";
          trafficType = "dns";
        }
        {
          name = "opal-dns";
          providerNode = "core-vpn-opal";
          addressAuthority = "model-allocated-service-prefix";
          trafficType = "dns";
        }
      ];

      relations = [
        (allowFromTo "allow-clients-vpn-to-onyx-dns" 86 (tenantRef "cobalt-clients-vpn") (serviceRef "onyx-dns") "dns")
        (allowFromTo "allow-onyx-dns-to-onyx" 90 (serviceRef "onyx-dns") { kind = "external"; scope = "core-vpn-onyx"; } "dns")
        (allowFromTo "allow-clients-vpn-to-opal-dns" 86 (tenantRef "cobalt-clients-vpn") (serviceRef "opal-dns") "dns")
        (allowFromTo "allow-opal-dns-to-opal" 90 (serviceRef "opal-dns") { kind = "external"; scope = "core-vpn-opal"; } "dns")
        (allowFromTo "allow-clients-to-core-dns" 87 (tenantRef "cobalt-clients") (serviceRef "core-dns") "dns")
        (allowResolverToCoreDns "clients-dns" 88)
        (allowFromTo "allow-mgmt-to-core-dns" 89 (tenantRef "cobalt-mgmt") (serviceRef "core-dns") "dns")
        (allowResolverToCoreDns "mgmt-dns" 90)
        (allowResolverToCoreDns "svc-dns" 89)
        (allowFromTo "allow-core-dns-to-wan" 90 (serviceRef "core-dns") coreScope "dns")
        (denyFromTo "deny-clients-dns-to-wan" 92 (serviceRef "clients-dns") coreScope "dns")
        (denyFromTo "deny-svc-dns-to-wan" 93 (serviceRef "svc-dns") coreScope "dns")
        (allowResolverToCoreDns "iot-dns" 94)
        (allowResolverToCoreDns "iot-srv-dns" 95)
        (allowResolverToResolver "clients-vpn-dns" "onyx-dns" 96)
        (allowResolverToResolver "clients-vpn-dns" "opal-dns" 96)
      ];

      bindings = [
        (recursiveDnsBinding "clients-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "svc-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "iot-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "iot-srv-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "mgmt-dns" "core-dns" "core" "wan")
        (recursiveDnsBinding "clients-vpn-dns" "onyx-dns" "core-vpn-onyx" "onyx")
        (recursiveDnsBinding "clients-vpn-dns" "opal-dns" "core-vpn-opal" "opal")
      ];
    };

    localDnsSharingIntent = [
      {
        namespace = "home.arpa.";
        authority = {
          service = "clients-dns";
          records = [
            "clients-kea-local-data"
            "dmz-static-local-data"
          ];
        };
        requester = {
          service = "dmz-dns";
          allowedNamespaces = [
            "home.arpa."
            "30.2.10.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = dnsSharingRelation "allow-dmz-dns-to-clients-dns" "dmz-dns" "clients-dns";
        providerPolicy = refuseNonLocalProvider "dmz-dns";
        lateralPolicy = {
          source = "cobalt-clients";
          target = "dmz-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
      {
        namespace = "home.arpa.";
        authority = {
          service = "unlock-dns";
          records = [
            "unlock-static-local-data"
          ];
        };
        requester = {
          service = "clients-dns";
          allowedNamespaces = [
            "unlock.home.arpa."
            "90.2.10.in-addr.arpa."
          ];
          recursion = false;
          publicFallback = false;
        };
        relation = dnsSharingRelation "allow-clients-dns-to-unlock-dns" "clients-dns" "unlock-dns";
        providerPolicy = refuseNonLocalProvider "clients-dns";
        lateralPolicy = {
          source = "cobalt-unlock";
          target = "clients-dns";
          localData = true;
          recursion = false;
          transitiveEgress = false;
          action = "refuse_non_local";
        };
      }
    ];

    topology = {
      nodes = {
        core = {
          role = "core";
          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              egress.ipv4.translation = {
                mode = "nat44";
              };
            };
          };
        };

        core-vpn-onyx = {
          role = "core";
          uplinks = {
            onyx = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
              egress.ipv4.translation = {
                mode = "nat44";
              };
              egress.ipv6.translation = {
                mode = "nat66";
                translatedPrefixes = [ "fd42:dead:feed:c1e::/64" ];
              };
            };
          };
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-iot-srv";
            }
          ];
        };

        core-vpn-opal = {
          role = "core";
          uplinks = {
            opal = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
              egress.ipv4.translation = {
                mode = "nat44";
              };
              egress.ipv6.translation = {
                mode = "nat66";
                translatedPrefixes = [ "fd42:dead:feed:c1f::/64" ];
              };
            };
          };
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-iot-srv";
            }
          ];
        };

        # Service-only peer overlay (NAS, printer, future vlan10+ services).
        # It selects the peer site's service scopes, which own their prefixes
        # (FS-322), and offers no default: an egress (default offers 0.0.0.0/0
        # and ::/0) is not modeled here.
        core-vpn-garnet-cobalt = {
          role = "core";

          selects = [
            "access-svc"
            "access-dmz"
          ];
        };

        upstream-selector = {
          role = "upstream-selector";
        };

        policy = {
          role = "policy";
        };

        downstream-selector = {
          role = "downstream-selector";
        };

        access-svc = accessNode { tenant = "cobalt-svc"; selects = [ "wan" ]; };

        access-clients = accessNode { tenant = "cobalt-clients"; selects = [ "wan" ]; };

        access-iot = accessNode { tenant = "cobalt-iot"; selects = [ "wan" ]; };

        access-iot-srv = accessNode { tenant = "cobalt-iot-srv"; selects = [ "wan" ]; };

        access-dmz = accessNode { tenant = "cobalt-dmz"; };

        access-clients-vpn = {

          # FS-481: the two VPN providers are equal-cost members of one
          # selection; the selection requires explicit per-member liveness and
          # concurrent equal-cost use. The behaviors are intent; the renderer
          # must not infer them from the member count.
          behaviors = [

            "liveness"

            "equal-cost-multipath"

          ];

          selects = [

            "onyx"

            "opal"

          ];

          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "cobalt-clients-vpn";
            }
          ];
        };

        access-unlock = accessNode { tenant = "cobalt-unlock"; };

        access-mgmt = accessNode { tenant = "cobalt-mgmt"; selects = [ "wan" ]; };
      };

      links = [
        [ "core" "upstream-selector" ]
        [ "core-vpn-onyx" "upstream-selector" ]
        [ "core-vpn-opal" "upstream-selector" ]
        [ "core-vpn-garnet-cobalt" "upstream-selector" ]
        [ "upstream-selector" "policy" ]
        [ "policy" "downstream-selector" ]
        [ "downstream-selector" "access-svc" ]
        [ "downstream-selector" "access-clients" ]
        [ "downstream-selector" "access-dmz" ]
        [ "downstream-selector" "access-iot-srv" ]
        [ "downstream-selector" "access-iot" ]
        [ "downstream-selector" "access-clients-vpn" ]
        [ "downstream-selector" "access-unlock" ]
        [ "downstream-selector" "access-mgmt" ]
      ];
    };

    transport = {
      overlays = [
        {
          name = "onyx";
          terminateOn = [ "core-vpn-onyx" ];
          underlayAccess = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
        }
        {
          name = "opal";
          terminateOn = [ "core-vpn-opal" ];
          underlayAccess = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
        }
        {
          name = "garnet";
          terminateOn = "core-vpn-garnet-cobalt";
          peerSite = "esp0xdeadbeef.neon";
          mustTraverse = [ "policy" ];
          underlayAccess = {
            kind = "tenant";
            name = "cobalt-iot-srv";
          };
          # Mirror of the neon garnet overlay (URS: overlay transport models
          # endpoint identity, permitted peers, and imported/exported prefixes).
          # cobalt-svc's prefix is exported; neon's vlan3 prefix is imported so
          # cobalt routes to the LLM server.  The peer's garnet participant
          # address is the next hop for those imported prefixes; a peer site is
          # not compiled in this site's pass, so it is modeled here (the peer
          # node address is an inventory realization fact mirrored onto the
          # overlay as its endpoint identity).
          peerNodes = {
            "esp0xdeadbeef.neon" = {
              addr4 = "10.80.0.1/24";
              addr6 = "fd42:dead:beef:80::1/64";
            };
          };
          prefixes = {
            exported = {
              ipv4 = [ "10.2.20.0/24" ];
              ipv6 = [ "fd42:dead:beef:220::/64" ];
            };
            imported = {
              ipv4 = [ "192.168.3.0/24" ];
              ipv6 = [ "fd42:dead:beef:3::/64" ];
            };
          };
        }
      ];
    };
  };
}
