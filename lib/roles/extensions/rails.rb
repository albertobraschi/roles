class Privileges::Base
  class << self
    def after_find(model_sym, &blk)
      install_callback :after_find, model_sym, &blk
    end
  
    def after_find_collection(model_sym, &blk)
      install_callback :after_find_collection, model_sym, &blk
    end
    
    private
    
    def install_callback(method_name, model_sym, &blk)
      module_name = "#{model_sym.to_s.classify}FindCallbacks"
      constant = if self.const_defined?(module_name)
        self.const_get(module_name)
      else
        self.const_set(module_name, Module.new)
      end
      constant.instance_eval do 
        define_method(method_name) do |*args|
          blk.call *args
        end
      end          
    end
  end
  
  
  class ActiveRecordProxy < BlankSlate
    CALLBACK_METHOD_REGEXP = /^((all|first|last)|find_.*)$/

    def initialize(obj_to_proxy, proxy_source, activerecord_class=nil)
      @obj_to_proxy = obj_to_proxy
      @proxy_source = proxy_source
      @activerecord_class = activerecord_class || @obj_to_proxy
    end
    
    def method_missing(method_name, *args, &blk)
      result = @obj_to_proxy.send method_name, *args, &blk

      if proxy_object_is_ancestor_of? ActiveRecord::Base
        find_and_execute_class_level_find_callbacks_for method_name, result
      end

      if result.kind_of?(ActiveRecord::Base)
        find_and_mixin_custom_module_functionality result
        result
      else
        ActiveRecordProxy.new result, @proxy_source, @activerecord_class
      end
    end
    
  private
  
    def proxy_object_is_ancestor_of?(klass)
      @obj_to_proxy.respond_to?(:ancestors) && @obj_to_proxy.ancestors.include?(klass)
    end
    
    def find_and_mixin_custom_module_functionality(record)
      module_name = "#{record.class.name}Methods"
      if @proxy_source.class.const_defined?(module_name)
        record.extend @proxy_source.class.const_get(module_name)
      end
    end
    
    def find_and_execute_class_level_find_callbacks_for method_name, record_or_records
      if method_name.to_s =~ CALLBACK_METHOD_REGEXP
        namespace = @activerecord_class.name
        if record_or_records.is_a?(Array)
          dispatch_method = "after_find_collection"
        else
          dispatch_method = "after_find"
        end
        module_name = "#{namespace}FindCallbacks"
        if @proxy_source.class.const_defined?(module_name)
          constant = @proxy_source.class.const_get(module_name)
          if constant.instance_methods.include?(dispatch_method)
            Object.new.extend(constant).send dispatch_method, record_or_records, @proxy_source.source
          end
        end
      end
    end

  end
end