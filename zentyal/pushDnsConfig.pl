#!/usr/bin/perl

use strict;
use warnings;
use EBox;
use EBox::Global;
use EBox::Model::Manager;
use EBox::DNS;
use Data::Dumper;
use JSON;

# Function: json_decode_file
# 
# Purpose: 
# 
#   Decodes the given UTF-8 encoded json file and returns the resulting data structure
# 
# Parameters:
#   $filename - Path of the file to parse
# 
# Returns: reference to the resulting object
#
sub json_decode_file{
  my ($filename) = @_;
  my $data;
  # Read the contents of the given UTF-8 JSON file into a string
  my $json_text = do{
    open(my $json_fh, "<:encoding(UTF-8)", $filename)
      or die("Unable to open file: $filename: $!\n");
    # $/ is the record separator, set it to undef instead of newline, so that <$json_fh> will read all lines at once
    local $/;
    <$json_fh>
  };
  # Attempt to decode the json
  eval {$data = decode_json($json_text)};
  if ($@){
    # If an error occured during the decoding process (likely due to incorrect format)
    die ("Error parsing json from file: $filename, error text: $@\n");
  }
  return $data;
}

# Function: dropDomainIfExists
# 
# Purpose: 
# 
#   Drops the provided domain and the configuration if it exists
# 
# Parameters:
#   $dns          - DNS module instance obtained from EBox::Global->getInstance()->modInstance('dns') after EBox::init();
#   $domain_name  - Name of the domain, ex: example.com
# 
# Returns: nothing
#
sub dropDomainIfExists{
  my ($dns, $domain_name) = @_;
  my $dmn_id;
  # Attempt to find the entry with the given name
  eval {$dmn_id = $dns->model('DomainTable')->_getDomainRow($domain_name)->id()};
  if (!$@){
    # If results were returned, remove the domain with the given name
    $dns->model('DomainTable')->removeRow($dmn_id);
  }
}

# Function: refreshDNS
# 
# Purpose: 
# 
#   Refreshes DNS information in Zentyal with the information located in the provided json configuration file
#     On success, will save the configuration. 
#     On failure, will revert back to last saved configuration
# 
# Parameters:
#   $dns          - DNS module instance obtained from EBox::Global->getInstance()->modInstance('dns') after EBox::init();
#   $config_file  - Path to JSON file, see below for example format:
# [
# 	{
# 		"domain_name":"example.com",
# 		"entries":[
# 			{
# 				"name":"web",
# 				"ipAddresses":[
# 					"192.168.1.100",
# 					"192.168.1.101"
# 				]
# 			}
# 		]
# 	}
# ]
# Returns: nothing
#
sub refreshDNS{
  my ($dns, $config_file) = @_;
  my $dns_config = json_decode_file($config_file);
  my $errors_occured = 0;
	# loop through list of domain entries contained in the config
  foreach my $domain_entry (@$dns_config){
    my $domain_name = %$domain_entry{domain_name};
    my $domain_entries = %$domain_entry{entries};
    if(!$domain_name){
			# The domain name is required and can't be null, if it fails that criteria, set the errors_occured flag and break
      $errors_occured = 1;
      last;
    }
		# Drop the domain if it exists so it can be recreated based on the new config
    dropDomainIfExists($dns, $domain_name);
		# Attempt to add the domain and the provided entries
    eval{$dns->model('DomainTable')->addDomain({domain_name=>$domain_name, hostnames=>$domain_entries})};
    if($@){
			# If an error occured during the addition, set the errors_occured flag and break
      $errors_occured = 1;
      last;
    }
  }
  if($errors_occured){
    print "Error occured when refreshing configurations, restoring original configuration\n";
		if($@){
			print "$@";
		}
    $dns->revokeConfig();
  }
  else{
    print "Successful refresh of domain config from file: $config_file\n";
    $dns->saveConfigRecursive();
  }
}

# Init and get DNS instance
EBox::init();
my $global = EBox::Global->getInstance();
my $dns = $global->modInstance('dns');

my $dns_config = $ARGV[0];
if(!$dns_config){
  die("DNS configuration file path required\n");
}
else{
  print "Using DNS configuration file located in '$dns_config'\n";
}
# Attempt to refresh DNS configuration
refreshDNS($dns, $dns_config);