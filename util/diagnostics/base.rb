if RUBY_VERSION < "1.9"
  require File.dirname(__FILE__) / "mri_args"
else
  require File.dirname(__FILE__) / "vm_args"
end

module Diagnostics
  module Base

  end
end


if Rails.env == "garret"
  class GarretLogger < Logger
    def format_message(severity, timestamp, progname, msg)
      "#{msg}\n"
    end
  end
  logfile = File.open(Rails.root + 'log/gdev.log', File::WRONLY|File::APPEND|File::CREAT, 0666)
  logfile.sync = true
  Glog = GarretLogger.new(logfile)

  class Object
    def glog(mssg)
      Glog.info(mssg)
    end
  end
else
  class Object
    def glog(mssg)
    end
  end
end