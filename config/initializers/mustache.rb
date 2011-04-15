require 'action_view'
require 'active_support'
require 'mustache'

class Mustache

  # TODO - Think about allowing to overwrite layout methods in subclassing views
  #
  # http://github.com/defunkt/mustache/blob/master/lib/mustache/sinatra.rb#L79-82
  # http://github.com/defunkt/mustache/blob/master/lib/mustache/sinatra.rb#L96-102

  # Remember to use {{{yield}}} (3 mustaches) as this shouldn't be escaped.
  # Using {{{tag}}} will skip escaping HTML so if your mustache methods return
  # HTML, be sure to interpolate them using 3 mustaches.

  # Subclass Mustache::Rails for your view files. You should place view files in
  # app/views/:controller/:action.rb. Mustache::Rails registers a TemplateHandler
  # for ".rb" files. Templates go to app/templates/:controller/:action.format.mustache

  class Rails < Mustache
    attr_accessor :view

    def method_missing(method, *args, &block)
      view.send(method, *args, &block)
    end

    def respond_to?(method, include_private=false)
      super(method, include_private) || view.respond_to?(method, include_private)
    end

    # Redefine where Mustache::Rails templates locate their partials:
    #
    # (1) in the same directory as the current template file.
    # (2) in the shared templates path (can be configured via Config.shared_path=(value))
    #
    def partial(name)
      partial_name = "#{name}.#{Config.template_extension}"
      template_dir = Pathname.new(self.class.template_file).dirname
      partial_path = File.expand_path("#{template_dir}/#{partial_name}")
      unless File.file?(partial_path)
        partial_path = "#{Config.shared_path}/#{partial_name}"
      end
      File.read(partial_path)
    end

    # You can change these defaults in, say, a Rails initializer or
    # environment.rb, e.g.:
    #
    # Mustache::Rails::Config.template_base_path = Rails.root.join('app', 'templates')
    module Config
      def self.template_base_path
        @template_base_path ||= ::Rails.root.join('app', 'templates')
      end

      def self.template_base_path=(value)
        @template_base_path = value
      end

      def self.template_extension
        @template_extension ||= 'html.mustache'
      end

      def self.template_extension=(value)
        @template_extension = value
      end

      def self.shared_path
        @shared_path ||= ::Rails.root.join('app', 'templates', 'shared')
      end

      def self.shared_path=(value)
        @shared_path = value
      end
    end

    class TemplateHandler < ActionView::Template::Handler

      include ActionView::Template::Handlers::Compilable

      self.default_format = :mustache

      # @return [String] its evaled in the context of the action view
      # hence the hack below
      #
      # @param [ActionView::Template]
      def compile(template)
        mustache_class = mustache_class_from_template(template)
        mustache_class.template_file = mustache_template_file(template)
        <<-MUSTACHE
          mustache = ::#{mustache_class}.new
          mustache.view = self
          mustache[:yield] = content_for(:layout)
          mustache.context.update(local_assigns)
          mustache.render
        MUSTACHE
      end

    private

      def copy_instance_variables_to(mustache)
        variables = @view.controller.instance_variable_names
        variables -= %w[@template]

        if @view.controller.respond_to?(:protected_instance_variables)
          variables -= @view.controller.protected_instance_variables
        end

        variables.each do |name|
          mustache.instance_variable_set(name, @view.controller.instance_variable_get(name))
        end

        # For an anonymous mustache, you probably want +attr_reader+ declared for
        # your instance variables. Otherwise there's no way you can access them on
        # the template.
        if mustache.class == Mustache
          mustache.class.class_eval do
            attr_reader *variables.select { |name| name =~ /^@[^_]/ }
          end
        end
      end

      def mustache_class_from_template(template)
        const_name = ActiveSupport::Inflector.camelize(template.virtual_path.to_s)
        defined?(const_name) ? const_name.constantize : Mustache
      end

      def mustache_template_file(template)
        "#{Config.template_base_path}/#{template.virtual_path}.#{Config.template_extension}"
      end

    end
  end
end

::ActiveSupport::Dependencies.autoload_paths << Rails.root.join("app", "views")
::ActionView::Template.register_template_handler(:rb, Mustache::Rails::TemplateHandler)
