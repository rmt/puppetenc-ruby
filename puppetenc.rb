#
# PuppetENC provides the ENCEvaluator class that lets you
# do intelligent addition/removal of classes and parameters,
# as well as variable substitution based on an include
# hierarchy.
#
# node = "mynode"
# nodedata = make_node_data(node)
# myloader = YAMLLoader.new("/path/to/yaml")
# enc = PuppetENC.new(node, nodedata, myloader)
# enc.include("node/")
#

module PuppetENC
  #
  class PuppetENCException < StandardError; end
  class TooManyIncludesException < PuppetENCException; end
  class InvalidIncludesFormat < PuppetENCException; end
  class RecursionException < PuppetENCException; end
  class HashExpectedException < PuppetENCException; end

  #
  # ENCLeaf is an encapsulation of classes, parameters, includes, and
  # vars (and possibly more).  Leaf is probably a poor name,
  # since we're not using a tree, although I suppose that a list
  # is just a branchless tree. :-)
  #
  class ENCLeaf
    attr_reader :name, :data

    def initialize(name, data)
      @name = name
      @data = data
    end

    # return a normalized hash of classes
    def classes()
      result = @data["classes"] || {}
      raise HashExpectedException.new() unless result.class == Hash
      return result
    end

    # return a normalised hash of parameters
    def parameters()
      result = @data["parameters"] || {}
      raise HashExpectedException.new() unless result.class == Hash
      return result
    end

    # Return a normalised list of includes, or an empty list.
    def includes()
      includes = @data["includes"]
      if includes.nil? || includes == ""
        return []
      elsif includes.class == String
        return [includes]
      elsif includes.class == Array
        return includes
      else
        raise InvalidIncludesFormat.new("Value for 'includes' in #{@name} must be a String or an Array, (#{includes.inspect})")
      end
    end

    # Lookup the given key.
    # Return true, value if we have the variable.
    # Return false, nil if we don't.
    def lookup(key)
      if @data["vars"] && @data["vars"].has_key?(key)
        return true, @data["vars"][key]
      end
      return false, nil
    end
  end

  #
  # Instantiate with a node name, node data, and a loader object (which has the
  # load(name) method which returns a dict).  Then call the include method one
  # or more times to set the include/override order. After this, the
  # ENCEvaluator object is ready to do overrides and variable substitutions,
  # eventually spitting out a classes hash and a parameters hash.  It can also
  # be used for individual overridable variable lookup on top of the extra
  # support for classes/parameters.
  #
  # Configurable variables:
  # - allow_includes - default is true
  # - max_include_depth - default is 32
  # - plugins - an empty list, to which you can append plugins which satisfy
  #   the following interface:
  #   * lookup(key) - return [true, some_value] or [false, nil] if not found
  #   * evaluate() - do something during the ENCEvaluator.evaluate() method,
  #     after include's are done, but before classes & parameters are
  #     substituted.
  #
  class ENCEvaluator
    attr_reader :name
    attr_accessor :max_include_depth, :allow_includes, :override_list, :plugins, :loader

    def initialize(node_name, node_data, loader)
      @node = ENCLeaf.new(node_name, node_data)
      @loader = loader
      @plugins = []
      @override_list = []
      @log = []
      @max_include_depth = 32
      @allow_includes = true
      @lookup_cache = {}
      log("ENCEvaluator", "instantiated (#{name})")
    end

    def get_log()
      @log
    end

    # every log message must have a context
    def log(context, msg)
      @log << "#{context}: #{msg}"
    end

    # create ENCLeaf's, appending included files to @override_list
    def include(name)
      if @override_list.length > @max_include_depth
        raise TooManyIncludesException.new("Maximum of #{@max_include_depth} chained includes exceeded. Do you have a loop?")
      end
      data = @loader.load(name)
      if data.nil?
        log("include(#{name})", "NotFound, ignoring.")
      elsif data.class != Hash
        log("include(#{name})", "NotHash, ignoring.")
      else
        log("include(#{name})", "Loaded")
        leaf = ENCLeaf.new(name, data)
        @override_list << leaf
        # now, if there's an includes section, include them.
        if @allow_includes && leaf.includes().length > 0
          include_list = []
          # 1. evaluate include names in the current context
          leaf.includes().each do |include_name|
            # include's will usually require substitution
            include_name = subst(name, include_name)
            include_list << include_name if include_name
          end # includes each
          # 2. then include them in order
          include_list.each do |include_name|
            include(include_name) if include_name
          end
        end
      end
    end

    def flat_classes()
      flat_classes = {}
      ([@node]+@override_list).each do |leaf|
        leaf.classes().each do |class_name, hash|
          log(leaf.name, "SetClass (#{class_name})")
          if hash == nil || hash == false || hash == true
            flat_classes[class_name] = hash
          else
            flat_classes[class_name] = hash.dup
          end
        end
      end
      return flat_classes
    end

    def classes()
      classes = flat_classes()
      classes.keys.each do |class_name|
        classes[class_name] = class_hash = subst(class_name, classes[class_name])
        @classes.delete(class_name) if class_hash == false # support total removal of classes
      end
      return classes
    end

    def flat_parameters()
      flat_parameters = {}
      ([@node]+@override_list).each do |leaf|
        leaf.parameters().each do |k,v|
          log(leaf.name, "SetParameter (#{k} => #{v})")
          if v == nil || v == false || v == true
            flat_parameters[k] = v
          else
            flat_parameters[k] = v.dup
          end
        end
      end
      return flat_parameters
    end

    def parameters()
      parameters = flat_parameters()
      parameters.keys.each do |param_name|
        parameters[param_name] = value = subst(param_name, parameters[param_name])
        parameters.delete(param_name) if value.nil?
      end
      return parameters
    end

    # Convert certain string values to literal types
    def convert_literals(value)
      if value == "#nil"
        return nil
      elsif value == "#true"
        return true
      elsif value == "#false"
        return false
      else
        return value
      end
    end

    # Lookup a single variable's value by traversing the override stack.
    # It assumes that ${ and } have already been stripped.
    def lookup(context, key)
      # default is nil by default (ie. remove), but allow for other defaults
      # using the ${varname:default} syntax.
      if key =~ /^\[(.*)\]$/ # support for ${[some literal string]}
        return $1
      elsif key =~ /^([_.a-zA-Z0-9]+):(.*?)$/
        default = $2
        varname = $1
      elsif key =~ /^([_.a-zA-Z0-9]+)$/
        default = nil
        varname = $1
      else
        log(context, "InvalidChars in variable name, setting to nil (#{key} => nil)")
        return nil
      end

      # Is the variable in the lookup cache?
      if @lookup_cache.has_key?(varname)
        log(context, "VarFound in lookup_cache (#{varname} => #{@lookup_cache[varname]})")
        return @lookup_cache[varname]
      end

      # Ask plugins first..
      @plugins.each do |plugin|
        next unless plugin.respond_to?(:name) && plugin.respond_to?(:lookup)
        found, result = plugin.lookup(key)
        if found
          log(context, "VarFound in plugin #{plugin.name} (#{varname} => #{result.inspect})")
          @lookup_cache[varname] = result
          return result
        end
      end

      # We now search for a variable from the most-specific leaf to the least-specific,
      # which means node first, then the reversed override_list.
      lookup_list = [@node] + (@override_list.reverse)
      log("evaluate", "lookup_list is [#{lookup_list.map {|x| x.name}.join(', ')}]")
      lookup_list.each do |leaf|
        found, result = leaf.lookup(varname) # TODO: we still have to handle nil etc.
        if found
          log(context, "VarFound in #{leaf.name} (#{varname} => #{result.inspect})")
          result = convert_literals(result)
          @lookup_cache[varname] = result
          return result
        end
      end
      log(context, "VarNotFound. Using default value (#{varname} => #{default.inspect})")
      @lookup_cache[varname] = default
      return default
    end

    # NOTE: Do not modify original data structures. Return new ones.
    def subst(context, value)
      # if it's a Hash, call subst for each value
      if value.class == Hash
        new_hash = {}
        value.each do |key, val|
          new_val = subst("#{context}.#{key}", val)
          # Only include non-nil values in ENC results..
          # This allows Puppet defaults to work.
          new_hash[key] = new_val unless new_val.nil?
        end
        return new_hash
      # if it's an Array, call subst for each item
      elsif value.class == Array
        new_value = []
        i=0
        value.each do |val|
          new_value << subst("#{context}.#{i}", val)
          i += 1
        end
        return new_value
      end

      # only 
      return value if value.class != String

      # if no variables, just return it
      return value unless value =~ /\$\{.*?\}/

      # Iterate through all matches and perform 
      # If there is only one variable, don't convert to a string.
      # 
      # - NilClass ("nil" gets converted to nil)
      # - TrueClass ("true" gets converted to true)
      # - FalseClass ("false" gets converted to false)
      # - Any other type that YAML supports
      looked_up = {} # track our lookups to avoid recursion
      result = value
      begin
        while result.class == String && result =~ /\$\{.*?\}/
          if result =~ /^\$\{([^}]+)\}$/
            raise RecursionException if looked_up[$1]
            looked_up[$1] = true
            result = lookup(context, $1)
          else
            result = result.gsub(/\$\{([^}]+)\}/) do
              raise RecursionException if looked_up[$1]
              looked_up[$1] = true
              lookup(context, $1).to_s
            end
          end
        end
      rescue RecursionException
        log(context, "RecursionException (#{value} => nil)")
        return nil
      end
      return result # finally!
    end

    # Perform the evaluation...
    def evaluate()
      log("evaluate", "begin ENC evaluation for #{@node.name}")
      log("evaluate", "override_list is [#{@override_list.map {|x| x.name}.join(', ')}]")
  
      @plugins.each do |plugin|
        next unless plugin.respond_to?(:name) && plugin.respond_to?(:evaluate)
        log("evaluate", "Calling #{plugin.name}.evaluate()")
        plugin.evaluate()
      end
  
      # and finally return the result
      return {
        "classes" => classes(),
        "parameters" => parameters(),
      }
    end
  end
end # module PuppetENC
