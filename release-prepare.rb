#!/usr/bin/env ruby
#From comment on: Script to assist to release:prepare for unusual versions http://jira.codehaus.org/browse/MRELEASE-511

require 'pty'
require 'expect'
require 'rexml/document'

#http://stackoverflow.com/questions/10238298/ruby-on-linux-pty-goes-away-without-eof-raises-errnoeio
module SafePty
  def self.spawn command, &block
    PTY.spawn(command) do |r,w,p|
      begin
        yield r,w,p
      rescue Errno::EIO
      ensure
        Process.wait p
      end
    end
    $?.exitstatus
  end
end

def make_new_development_version(release_version) 
	#Remove the last digit and increment it
	m = /(?<r>.*)(?<v>\d+)$/.match(release_version)
	if (m)
		next_ver = m[:v].to_i + 1
		return "#{m[:r]}#{next_ver}-SNAPSHOT"
	end
end

def reset(line)
	print line
	return ""
end


#Provide option to read base_dir from command line
base_dir = Dir.pwd

pom_file = base_dir + "/pom.xml"

raise "Can't read #{pom_file}" unless File.readable? pom_file

pom = REXML::Document.new(File.new(pom_file))

raise "Can't find project version in #{pom_file}" unless pom.elements['project/version']
raise "Can't find artifactId in #{pom_file}" unless pom.elements['project/artifactId']

version = pom.elements['project/version'].text
artifact = pom.elements['project/artifactId'].text

release_version = version.gsub(/-SNAPSHOT/,'')
scm_tag = "#{artifact}-" + release_version

# Write a make_new_development_version() function appropriate to 
# whatever format you're using for your version strings
development_version = make_new_development_version(release_version)

puts "Release Version: #{release_version}"
puts "Development Version: #{development_version}"
puts "Artifact: #{artifact}"

STDOUT.sync = true
STDERR.sync = true
$stdout.sync = true
$stderr.sync = true

#Don't do remote tagging
remoteTagging = "-DremoteTagging=false"

#Need to supply username and password
SafePty.spawn("mvn -Dresume=false #{remoteTagging} release:clean release:prepare") do |reader, writer, pid|
	reader.sync = true
	writer.sync = true
	line =  ""
	until reader.eof? do
		char = reader.getc.chr
		line << char
		case line 
			#These are all the possible things it could ask
			when /What is the release version for.+: :/
				line = reset(line)
				writer.puts(release_version) 
			when /What is SCM release tag or label for.+: :/
				line = reset(line)
				writer.puts(scm_tag)
			when /What is the new development version for.+: :/
				line = reset(line)
				writer.puts(development_version)
			else
			#Nothing
		end
		if (char == "\n")
			#Clear out buffer, didn't find it
			line=reset(line)
		end

	end
end

print "Make sure to run mvn release:perform now (if there was no FAILURE)!"
