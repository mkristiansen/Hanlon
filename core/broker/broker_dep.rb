# this file defines the list of classes to be loaded under broker
# here all the load files are maintained in the order of dependency
#
# This can be replace if we find a more meaningful method of loading classes

# level 1
require 'broker/base'

# level 2
require 'broker/chef'
require 'broker/puppet'
require 'broker/script'
