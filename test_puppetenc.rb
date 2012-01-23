#
# PuppetENC unit tests
#

require 'test/unit'
require 'puppetenc'

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

#class TestENC < Test::Unit::TestCase

#end
