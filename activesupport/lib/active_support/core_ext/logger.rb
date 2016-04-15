require 'active_support/core_ext/class/attribute_accessors'
require 'active_support/deprecation'

# Adds the 'around_level' method to Logger.
class Logger #:nodoc:
  def self.define_around_helper(level)
    module_eval <<-end_eval, __FILE__, __LINE__ + 1
      def around_#{level}(before_message, after_message)  # def around_debug(before_message, after_message, &block)
        self.#{level}(before_message)                     #   self.debug(before_message)
        return_value = yield(self)                        #   return_value = yield(self)
        self.#{level}(after_message)                      #   self.debug(after_message)
        return_value                                      #   return_value
      end                                                 # end
    end_eval
  end
  [:debug, :info, :error, :fatal].each {|level| define_around_helper(level) }
end

require 'logger'
require 'thread_safe'

# Extensions to the built-in Ruby logger.
#
# If you want to use the default log formatter as defined in the Ruby core, then you
# will need to set the formatter for the logger as in:
#
#   logger.formatter = Formatter.new
#
# You can then specify the datetime format, for example:
#
#   logger.datetime_format = "%Y-%m-%d"
#
# Note: This logger is deprecated in favor of ActiveSupport::BufferedLogger
class Logger
  ##
  # :singleton-method:
  # Set to false to disable the silencer
  cattr_accessor :silencer
  self.silencer = true
  attr_reader :local_levels

  alias :old_datetime_format= :datetime_format=
  # Logging date-time format (string passed to +strftime+). Ignored if the formatter
  # does not respond to datetime_format=.
  def datetime_format=(datetime_format)
    formatter.datetime_format = datetime_format if formatter.respond_to?(:datetime_format=)
  end

  alias :old_datetime_format :datetime_format
  # Get the logging datetime format. Returns nil if the formatter does not support
  # datetime formatting.
  def datetime_format
    formatter.datetime_format if formatter.respond_to?(:datetime_format)
  end

  alias :old_initialize :initialize
  # Overwrite initialize to set a default formatter.

  def initialize(*args)
    old_initialize(*args)
    self.formatter = SimpleFormatter.new
    @local_levels  = ThreadSafe::Cache.new(:initial_capacity => 2)
  end

  alias_method :old_add, :add
  def add(severity, message = nil, progname = nil, &block)
    return true if @logdev.nil? || (severity || UNKNOWN) < level
    old_add(severity, message, progname, &block)
  end

  Logger::Severity.constants.each do |severity|
    class_eval(<<-EOT, __FILE__, __LINE__ + 1)
      undef :#{severity.downcase}? if method_defined? :#{severity.downcase}?
      def #{severity.downcase}?                # def debug?
        Logger::#{severity} >= level           #   DEBUG >= level
      end                                      # end
    EOT
  end

  def local_log_id
    Thread.current.__id__
  end

  def level
    local_levels[local_log_id] || @level
  end

  # Silences the logger for the duration of the block.
  def silence(temporary_level = Logger::ERROR)
    if silencer
      begin
        old_local_level            = local_levels[local_log_id]
        local_levels[local_log_id] = temporary_level

        yield self
      ensure
        if old_local_level
          local_levels[local_log_id] = old_local_level
        else
          local_levels.delete(local_log_id)
        end
      end
    else
      yield self
    end
  end
  deprecate :silence

  # Simple formatter which only displays the message.
  class SimpleFormatter < Logger::Formatter
    # This method is invoked when a log event occurs
    def call(severity, timestamp, progname, msg)
      "#{String === msg ? msg : msg.inspect}\n"
    end
  end
end
