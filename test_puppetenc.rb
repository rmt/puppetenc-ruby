#
# PuppetENC unit tests
#

require 'test/unit'
require 'puppetenc'
require 'yaml'

class TestENCLeaf < Test::Unit::TestCase

  def setup
    @hash = {
      "classes" => {
        "mysql_server" => {
          "datadir" => "${datadir:/var/lib/mysql/data}",
        }
      },
      "parameters" => {
        "paramFixnum" => 5,
        "paramBool" => false,
        "paramMissing" => "${notfound}",
      },
      "vars" => {
        "datadir" => "/data/mysql",
      },
    }
    @leaf = PuppetENC::ENCLeaf.new("mynode.example.com", @hash)
  end

  def test_classes
    assert_equal(["mysql_server"], @leaf.classes.keys)
  end

  def test_parameters
    assert_equal(@hash['parameters'], @leaf.parameters)
  end

  def test_includes_missing
    assert_equal(@leaf.includes, [])
  end

  def test_includes_with_empty_string
    @hash["includes"] = ""
    assert_equal([], @leaf.includes)
  end

  def test_includes_when_empty
    @hash["includes"] = []
    assert_equal([], @leaf.includes)
  end

  def test_includes_with_single_string
    @hash["includes"] = "foo"
    assert_equal(["foo"], @leaf.includes)
  end

  def test_includes_with_list
    @hash["includes"] = ["foo"]
    assert_equal(["foo"], @leaf.includes)
  end

  def test_lookup_success
    found, value = @leaf.lookup("datadir")
    assert_equal(true, found)
    assert_equal("/data/mysql", value)
  end

  def test_lookup_failure
    found, value = @leaf.lookup("notfound")
    assert_equal(false, found)
    assert_nil(value)
  end
end

class TestLoader
  def initialize(data)
    @data = data
  end
  def load(name)
    if @data.has_key?(name)
      return @data[name]
    else
      return nil
    end
  end
  def set(key, value)
    @data[key] = YAML.load(value)
  end
end

class TestENC < Test::Unit::TestCase
  def setup()
    @node_name = "test001"
    @node_data = {
      "parameters" => {
        "node_globalparam" => "${mystring}",
        "node_missingparam" => "${notfound}",
        "falseparam" => false,
        "nilparam" => nil,
      },
      "vars" => {
        "node.datacenter" => "london",
        "node.environment" => "production",
        "node.hostname" => "test001",
        "node.domain" => "example.com",
        "node.fqdn" => "test001.example.com",
        "node.module" => "helloworld",
        "node.release" => 15,
        "node.role" => "webserver",
        "node.owner" => 5551234,
        "node.site_release" => "10",
        "somevariable" => "white",
      },
    }
    @loader = TestLoader.new({})
    @loader.set 'global', <<-EOS
includes:
- node_${node.hostname}
- common_dc_${node.datacenter}
- common_env_${node.environment}
- common_dc_${node.datacenter}_env_${node.environment}
- common_platform_${node.site_release:trunk}
- module_${node.module}
- module_${node.module}_dc_${node.datacenter}
- module_${node.module}_env_${node.environment}
- module_${node.module}_dc_${node.datacenter}_env_${node.environment}
- module_${node.module}_release_${node.release}
- module_${node.module}_role_${node.role}_release_${node.release}
EOS
    @loader.set 'node_test001', <<-EOS
classes:
  dummyclass:
parameters:
  globalparam: ${mystring}
  dns_servers: ${dns_servers}
vars:
  dns_servers:
  - 1.2.3.4
  - 4.3.2.1
  mystring: foobar
  mynum: 5
  myfalse: '#false'
  mytrue: '#true'
  mynil: '#nil'
  realfalse: false
  realtrue: true
  realnil: null
  somevariable: "black"
EOS
    @loader.set 'module_helloworld', <<-EOS
vars:
  root_domain: "example.com"
  fqdn: "hello.test.${root_domain}"
EOS
    @loader.set 'module_helloworld_role_webserver_release_15', <<-EOS
classes:
  helloworld::webserver:
    fqdn: ${helloworld_fqdn}
    enable_ssl: ${helloworld_enable_ssl:#false}
EOS
    @loader.set 'module_helloworld_dc_london_env_production', <<-EOS
vars:
  helloworld_fqdn: hello.london.${root_domain}
  dns_servers:
  - 10.10.10.10
  - 10.10.20.10
EOS
    @enc = PuppetENC::ENCEvaluator.new(@node_name, @node_data, @loader)
  end
  
  def test_lookup_success
    assert_equal('london', @enc.lookup('context', 'node.datacenter'))
  end

  def test_lookup_failure
    assert_nil(@enc.lookup('context', 'not_found'))
  end

  def test_that_node_variable_always_looked_up_first
    assert_equal("white", @enc.lookup('context', 'somevariable'))
  end

  def test_nodeonly_subst_success
    assert_equal("london", @enc.subst('context', '${node.datacenter}'))
  end

  def test_nodeonly_subst_failure
    assert_nil(@enc.subst('context', '${missing_variable}'))
  end

  def test_nodeonly_subst_failure_as_string
    assert_equal('foo:', @enc.subst('context', 'foo:${missing_variable}'))
  end

  def test_includes
    @enc.include('global')
    assert_equal('foobar', @enc.lookup('context', 'mystring'))
    assert_equal([
      "global",
      "node_test001",
      "module_helloworld",
      "module_helloworld_dc_london_env_production",
      "module_helloworld_role_webserver_release_15",
    ],
    @enc.override_list.map { |x| x.name })
  end

  def test_vartypes
    @enc.include('global')
    assert_equal(5, @enc.lookup('context', 'mynum'))
    assert_equal(false, @enc.lookup('context', 'realfalse'))
    assert_equal(true, @enc.lookup('context', 'realtrue'))
    assert_equal(false, @enc.lookup('context', 'myfalse'))
    assert_equal(true, @enc.lookup('context', 'mytrue'))
    assert_equal(["10.10.10.10","10.10.20.10"], @enc.lookup('context', 'dns_servers'))
    assert_nil(@enc.lookup('context', 'mynil'))
    assert_nil(@enc.lookup('context', 'realnil'))
  end

  def test_subst
    @enc.include('global')
    assert_equal(true, @enc.subst('context', '${realtrue}'))
    assert_equal("string:true", @enc.subst('context', 'string:${realtrue}'))
  end

  def test_substituted_parameters
    @enc.include('global')
    parameters = @enc.parameters
    assert_equal("foobar", parameters['globalparam'])
    assert_equal("foobar", parameters['node_globalparam'])
    assert_nil(parameters["node_missingparam"]) # defined but not found
    assert(!parameters.has_key?('nilparam'))
    assert_equal(false, parameters['falseparam'])
  end

  def test_substituted_classes
    @enc.include('global')
    classes = @enc.classes
    assert_equal(['dummyclass', 'helloworld::webserver'], classes.keys.sort)
  end

  def test_subst_of_variable
    @enc.include('global')
    classes = @enc.classes
    assert_equal("hello.london.example.com", classes['helloworld::webserver']['fqdn'])
  end

  def test_subst_of_array
    @enc.include('global')
    result = @enc.subst('context', ["${node.hostname}", "${node.domain}"])
    assert_equal("test001", result[0])
    assert_equal("example.com", result[1])
  end

  class EmptyPlugin
  end

  def test_empty_plugin
    @enc.plugins << EmptyPlugin.new
    @enc.include('global')
    res = @enc.evaluate()
  end

  class BetterPlugin
    attr_reader :called
    def name
        return "betterplugin"
    end
    def lookup(key)
        return true, "Oz" if key == "wizard"
        return false, nil
    end
    def evaluate()
        @called = true
    end
  end

  def test_basic_plugin
    myplugin = BetterPlugin.new
    @enc.plugins << myplugin
    assert_equal('Oz', @enc.lookup('context', 'wizard'))
    assert_equal('test001', @enc.lookup('context', 'node.hostname'))
    @enc.evaluate()
    assert_equal(true, myplugin.called)
  end
end
