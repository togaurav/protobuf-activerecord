require 'heredity/inheritable_class_instance_variables'

module Protoable
  module Serialization
    def self.included(klass)
      klass.extend Protoable::Serialization::ClassMethods
      klass.__send__(:include, ::Heredity::InheritableClassInstanceVariables)

      klass.class_eval do
        class << self
          attr_accessor :_protobuf_attribute_converters,
            :_protobuf_field_transformers, :protobuf_fields
        end

        @_protobuf_attribute_converters = {}
        @_protobuf_field_transformers = {}
        @protobuf_fields = []

        inheritable_attributes :_protobuf_attribute_converters,
          :_protobuf_field_transformers, :protobuf_fields, :protobuf_message
      end
    end

    module ClassMethods
      # Define a field transformation from a record. Accepts a Symbol,
      # callable, or block that is called with the record being serialized.
      #
      # When given a callable or block, it is directly used to convert the field.
      #
      # When a symbol is given, it extracts the method with the same name.
      #
      # The callable or method must accept a single parameter, which is the
      # proto message.
      #
      # Examples:
      #   field_from_record :public_key, :convert_public_key_to_proto
      #   field_from_record :status, lambda { |record| # Do some stuff... }
      #   field_from_record :status do |record|
      #     # Do some blocky stuff...
      #   end
      #
      def field_from_record(field, transformer = nil, &blk)
        transformer ||= blk

        if transformer.is_a?(Symbol)
          callable = lambda { |value| self.__send__(transformer, value) }
        else
          callable = transformer
        end

        unless callable.respond_to?(:call)
          raise FieldTransformerError, 'Attribute transformers need a callable or block!'
        end

        _protobuf_field_transformers[field.to_sym] = callable
      end

      # Define a custom attribute conversion for serialization to protobuf.
      # Accepts a Symbol, Hash, callable or block.
      #
      # When given a callable or block, it is directly used to convert the field.
      #
      # When a Hash is given, :from and :to keys are expected and expand
      # to extracting a class method in the format of
      # "convert_#{from}_to_#{to}".
      #
      # When a symbol is given, it extracts the method with the same name.
      #
      # Examples:
      #   protoable_attribute :public_key, :extract_public_key_from_proto
      #   protoable_attribute :symmetric_key, :from => :base64, :to => :raw_string
      #   protoable_attribute :status, lambda { |proto_field| # Do stuff... }
      #   protoable_attribute :status do |proto_field|
      #     # Do some blocky stuff...
      #   end
      #
      def protoable_attribute(field, converter = nil, &blk)
        converter ||= blk
        converter = :"convert_#{converter[:from]}_to_#{converter[:to]}" if converter.is_a?(Hash)

        if converter.is_a?(Symbol)
          callable = lambda { |value| __send__(converter, value) }
        else
          callable = converter
        end

        unless callable.respond_to?(:call)
          raise AttributeConverterError, 'Attribute converters must be a callable or block!'
        end

        _protobuf_attribute_converters[field.to_sym] = callable
      end

      # Define the protobuf message class that should be used to serialize the
      # object to protobuf. Accepts a string or symbol.
      #
      # When protobuf_message is declared, Protoable automatically extracts the
      # fields from the message and automatically adds to_proto and to_proto_hash
      # methods that serialize the object to protobuf.
      #
      # Examples:
      #   protobuf_message :user_message
      #   protobuf_message "UserMessage"
      #   protobuf_message "Namespaced::UserMessage"
      #
      def protobuf_message(message = nil)
        unless message.nil?
          @protobuf_message = message.to_s.classify.constantize

          self.protobuf_fields = @protobuf_message.fields.compact.map do |field|
            field.name.to_sym
          end

          define_method(:to_proto) do
            self.class.protobuf_message.new(self.to_proto_hash)
          end

          define_method(:to_proto_hash) do
            protoable_attributes
          end
        end

        @protobuf_message
      end
    end

    # Extracts attributes that correspond to fields on the specified protobuf
    # message, performing any necessary column conversions on them.
    #
    def protoable_attributes
      protoable_attributes = protobuf_fields.inject({}) do |hash, field|
        if _protobuf_field_transformers.has_key?(field)
          hash[field] = _protobuf_field_transformers[field].call(self)
        else
          value = respond_to?(field) ? __send__(field) : nil
          hash[field] = _protobuf_convert_attributes_to_fields(field, value)
        end
        hash
      end

      protoable_attributes
    end

  private

    def _protobuf_convert_attributes_to_fields(field, value)
      self.class._protobuf_convert_attributes_to_fields(field, value)
    end

    def _protobuf_field_transformers
      self.class._protobuf_field_transformers
    end

    def protobuf_fields
      self.class.protobuf_fields
    end
  end
end
