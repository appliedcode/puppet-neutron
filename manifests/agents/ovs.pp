# == Class: neutron::agents::ovs
#
# Setups OVS neutron agent.
#
# === Parameters
#
# [*firewall_driver*]
#   (optional) Firewall driver for realizing neutron security group function.
#   Defaults to 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver'.
#
class neutron::agents::ovs (
  $package_ensure       = 'present',
  $enabled              = true,
  $bridge_uplinks       = [],
  $bridge_mappings      = [],
  $integration_bridge   = 'br-int',
  $enable_tunneling     = false,
  $local_ip             = false,
  $tunnel_bridge        = 'br-tun',
  $polling_interval     = 2,
  $firewall_driver      = 'neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver'
) {

  include neutron::params
  require vswitch::ovs

  if $enable_tunneling and ! $local_ip {
    fail('Local ip for ovs agent must be set when tunneling is enabled')
  }

  Neutron_config<||>     ~> Service['neutron-plugin-ovs-service']
  Neutron_plugin_ovs<||> ~> Service['neutron-plugin-ovs-service']

  if ($bridge_mappings != []) {
    # bridge_mappings are used to describe external networks that are
    # *directly* attached to this machine.
    # (This has nothing to do with VM-VM comms over neutron virtual networks.)
    # Typically, the network node - running L3 agent - will want one external
    # network (often this is on the control node) and the other nodes (all the
    # compute nodes) will want none at all.  The only other reason you will
    # want to add networks here is if you're using provider networks, in which
    # case you will name the network with bridge_mappings and add the server's
    # interfaces that are attached to that network with bridge_uplinks.
    # (The bridge names can be nearly anything, they just have to match between
    # mappings and uplinks; they're what the OVS switches will get named.)

    # Set config for bridges that we're going to create
    # The OVS neutron plugin will talk in terms of the networks in the bridge_mappings
    $br_map_str = join($bridge_mappings, ',')
    neutron_plugin_ovs {
      'OVS/bridge_mappings': value => $br_map_str;
    }
    neutron::plugins::ovs::bridge{ $bridge_mappings:
      before => Service['neutron-plugin-ovs-service'],
    }
    neutron::plugins::ovs::port{ $bridge_uplinks:
      before => Service['neutron-plugin-ovs-service'],
    }
  }

  neutron_plugin_ovs {
    'AGENT/polling_interval': value => $polling_interval;
    'OVS/integration_bridge': value => $integration_bridge;
  }

  if ($firewall_driver) {
    neutron_plugin_ovs { 'SECURITYGROUP/firewall_driver':
      value => $firewall_driver
    }
  } else {
    neutron_plugin_ovs { 'SECURITYGROUP/firewall_driver': ensure => absent }
  }

  vs_bridge { $integration_bridge:
    ensure => present,
    before => Service['neutron-plugin-ovs-service'],
  }

  if $enable_tunneling {
    vs_bridge { $tunnel_bridge:
      ensure => present,
      before => Service['neutron-plugin-ovs-service'],
    }
    neutron_plugin_ovs {
      'OVS/enable_tunneling': value => true;
      'OVS/tunnel_bridge':    value => $tunnel_bridge;
      'OVS/local_ip':         value => $local_ip;
    }
  } else {
    neutron_plugin_ovs {
      'OVS/enable_tunneling': value  => false;
      'OVS/tunnel_bridge':    ensure => absent;
      'OVS/local_ip':         ensure => absent;
    }
  }


  if $::neutron::params::ovs_agent_package {
    Package['neutron-plugin-ovs-agent'] -> Neutron_plugin_ovs<||>
    package { 'neutron-plugin-ovs-agent':
      ensure  => $package_ensure,
      name    => $::neutron::params::ovs_agent_package,
    }
  } else {
    # Some platforms (RedHat) do not provide a separate
    # neutron plugin ovs agent package. The configuration file for
    # the ovs agent is provided by the neutron ovs plugin package.
    Package['neutron-plugin-ovs'] -> Neutron_plugin_ovs<||>
    Package['neutron-plugin-ovs'] -> Service['ovs-cleanup-service']

    if ! defined(Package['neutron-plugin-ovs']) {
      package { 'neutron-plugin-ovs':
        ensure  => $package_ensure,
        name    => $::neutron::params::ovs_server_package,
      }
    }
  }

  if $enabled {
    $service_ensure = 'running'
  } else {
    $service_ensure = 'stopped'
  }

  service { 'neutron-plugin-ovs-service':
    ensure  => $service_ensure,
    name    => $::neutron::params::ovs_agent_service,
    enable  => $enabled,
    require => Class['neutron'],
  }

  if $::neutron::params::ovs_cleanup_service {
    service {'ovs-cleanup-service':
      ensure => $service_ensure,
      name   => $::neutron::params::ovs_cleanup_service,
      enable => $enabled,
    }
  }
}
