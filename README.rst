Puppet ENC
==========

A ruby library to help you write a featureful External Node Classifier for
Puppet, supporting contextual overrides of classes, parameters, and a special
set of substitutable variables.  It also supports dynamic includes, to add
additional override classes.

It assumes that you store your node information somewhere else already, and
that you can query your node information quickly, or otherwise programmatically
determine the next steps given a simple certname.

You must write a small loader to load a named ENC hash, and you must also
instantiate the ENCEvaluator class with the node name, an initial hash of node
data, and the data loader that you wrote.

You can see a good example of its use in the test_puppetenc.rb file.


What would you use this for?
----------------------------

Let's say that you have hundreds or thousands of servers running different
applications in different datacenters and different environments (eg.
production, test, etc.) across the globe.  Let's now say that you have a nice
LDAP database storing important node information, like what application it
should be running.

You could create a Puppet manifest for each of these nodes individually, and
try to keep that up to date manually with LDAP.  You could probably use node
templating to achieve some of what you want.  It can be made to work, but in my
opinion, it gets painful fast.

Instead, why not exploit your existing database to provide enough information
to say definitively how any given node should be configured.

You could configure release 9 of coolapp::webserver in a London datacenter in a
development environment, and very easily configure this same webserver for
London production, or a Tokyo Testing environment.

Simply put, an ENC like this one allows you to easily separate configuration
data (such as which DNS server to use or monitoring server to talk to or
credentials to use) from configuration logic (ie. puppet recipes), as well as
to easily integrate puppet with existing system databases.

An added side effect is that you can hand out responsibility for production
deployment and maintenance to a different team from the people who write the
puppet recipes.

Still don't get it?
-------------------

That's OK.  Not everyone runs into these problems of scale.  If you're only
configuring one or two systems, or every single one of your systems is
configured differently (or every system is identical), then you probably won't
have much use for software like this.

A small example
---------------

Let's assume that you store your ENC configuration data as YAML files in a
directory structure.  Let's say that you have a node (also represented as YAML
for convenience) which sets a few variables:

Node 'test001.de.example.com'::
  vars:
    hostname: test001
    country: de
    domain: de.example.com
    module: helloworld
    role: webserver

Let's say that you have a global include file::
  includes:
    - ${module}/${role}.yaml
    - ${module}/country/${country}.yaml

In the above, the two includes would lead to two files being included, if they exist::
  - helloworld/webserver.yaml
  - helloworld/country/de.yaml

In helloworld/webserver.yaml::
  vars:
    helloworld_text: "Hello, World!"
  classes:
    helloworld::webserver:
      text: ${helloworld_text}

In helloworld/country/de.yaml::
  vars:
    helloworld_text: "Hallo, Welt!"

For the given node, the ENC would evaluate to the following::
  classes:
    helloworld::webserver:
      text: "Hallo, Welt!"

This is because the text was overridden by the later-included country YAML file.


Let's say, however, that you have a node in the UK.  Node 'test001.uk.example.com'::
  vars:
    hostname: test001
    country: uk
    domain: uk.example.com
    module: helloworld
    role: webserver

It can use the same ENC files above to come up with different results.  In this
case, there is no helloworld/country/uk.yaml, so it uses the default defined in
helloworld/webserver.yaml (in the vars section).


Features
--------

* Override classes, parameters & variables in an order of your choosing
* Excellent test coverage
* Small and easy to integrate with existing data sources
* Support for plugins (eg. you want to dynamically generate variable substitutions, or add a new top-level key)
* Supports passing in lists & hashes, strings, nil/null, true, false, integers & floats.
* Substitute vars from other vars.

Top level keys
--------------

There are four top-level keys that are supported out of the box (extensible
with plugins).  I refer to this collection as a *leaf* (like on a tree, but this
tree has one trunk and no branches).

classes
  classes is a hash, containing class names as keys and hashes as class parameters. If a class has nil, the class
  will still be passed to puppet.  If the class value is set to false, the class will be removed (at this override level).
  All values will undergo substitution against the values in 'vars' if they match a substitution form.  Nested structures
  will have their values substituted also.  Class parameters whose values resolve to 'nil' will be removed from the class
  parameter hash, to enable puppet defaults to work as expected.

parameters
  parameters is a hash, containing parameter names as keys and their values, which will undergo substitution. Parameters
  whose values are 'nil' will be removed from the parameters hash.

vars
  vars is a hash, containing variables which will be available for substitution.  They will be overridden following the
  override order.

includes
  includes can be a list of ENC *leaves* to include. Each string will be subject to substitution from vars, but of course
  only the vars that are available at the time of including this particular *leaf* can be used for the substitution.

