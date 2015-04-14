if $servlet_context.nil?
  ENV['GEM_HOME'] = File.expand_path('../../WEB-INF', __FILE__)

  ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../WEB-INF/Gemfile', __FILE__)

else
  ENV['GEM_HOME'] = $servlet_context.getRealPath('/WEB-INF/lib/gems.jar')

  ENV['BUNDLE_GEMFILE'] ||= $servlet_context.getRealPath('/WEB-INF/Gemfile')

end

puts "public.root" + ENV['GEM_HOME']
