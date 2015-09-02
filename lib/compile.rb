require "fileutils"
require "asciidoctor"
require "asciidoctor-epub3"

# Implement our custom render of YouTube videos (asciidoctor-epub3 simply strips them out)
module Asciidoctor
  module Epub3
    class ContentConverter
        def video(node)
            videoID = node.attr 'target'
            url = "https://www.youtube.com/watch?v=" + videoID
            %(<p><a href="#{url}">Watch video on YouTube at #{url}</a></p>)
        end
    end
  end
end

$rootDir = File.expand_path(File.dirname(File.dirname(__FILE__)))

def process(which)
  print "Processing " + which + ":\n"

  print "  - EPUB... "
  stdOutString = StringIO.new
  stdOutOriginal = $stdout
  $stdout = stdOutString
  begin
    Asciidoctor.convert_file(which + ".adoc", :to_file => "output/" + which + ".epub", :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :backend => "epub3", :attributes => {"numbered" => true})
  ensure
    $stdout = stdOutOriginal
  end
  print "done.\n"

  print "  - Complete HTML... "
  adoc = Asciidoctor.convert_file(which + ".adoc", :to_file => false, :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :attributes => {"numbered" => true})
  adoc.gsub!('src="//www.youtube.com/', 'src="https://www.youtube.com/')
  f = File.open("output/" + which + ".html", "wb")
  f.write(adoc)
  f.close
  print "done.\n"

  print "  - Preparing files for DocBook... "
  Dir.mkdir("tmp/adoc") unless Dir.exists?("tmp/adoc")
  FileUtils.cp(which + ".adoc", "tmp/adoc/" + which + ".adoc")
  FileUtils.rm_rf("tmp/adoc/" + which)
  for step in 1..2
    Dir.glob(which + "/**/*").each do |fromPath|
      toPath = fromPath.sub(which + "/", "tmp/adoc/" + which + "/")
      if File.directory?(fromPath)
        if step == 1
          FileUtils.mkdir_p(toPath) unless Dir.exists?(toPath)
        end
      else
        if step == 2
          if /\.adoc$/ =~ toPath
            relPathAdoc = fromPath.sub(which + "/", "")
            relPathHtml = relPathAdoc.sub(/\.adoc$/, '.html')
            f = File.open(fromPath, "rb")
            contents = f.read
            f.close
            # Specify output file name, add link to edit on GitHub
            contents.gsub!(/^(= .*?\n)/, "\\1++++\n<?dbhtml filename=\"" + relPathHtml + "\"?>\n++++\n\n++++\n<simpara role=\"c5-edit-this-page\"><link xlink:href=\"https://github.com/concrete5/concrete5-documentation/tree/master/" + which + "/" + relPathAdoc + "\">Edit on GitHub</link></simpara>\n++++\n\n")
            # Fix images URL
            contents.gsub!(/^(image:+)/, '\1https://raw.githubusercontent.com/concrete5/concrete5-documentation/master/images/developers/')
            # Fix YouTube videos
            while true do
              rxMatch = /^video::?(?<id>[\w\-]+)\s*\[\s*youtube\b(?<params>[^\]]*)\]\s*$/i.match(contents)
              if rxMatch.nil?
                break
              end
              search = rxMatch[0]
              videoID = rxMatch['id']
              videoParams = rxMatch['params']
              videoWidth = nil
              rxMatch = /,\s*width\s*=\s*(?<num>\d+)/i.match(videoParams);
              if !rxMatch.nil?
                videoWidth = rxMatch['num']
              end
              videoHeight = nil
              rxMatch = /,\s*height\s*=\s*(?<num>\d+)/i.match(videoParams);
              if !rxMatch.nil?
                videoHeight = rxMatch['num']
              end
              replace = "++++\n"
              replace << "<mediaobject>\n"
              replace << "\t<videoobject>\n"
              replace << "\t\t<videodata fileref=\"https://www.youtube.com/embed/" + videoID + "\""
              if !videoWidth.nil?
                replace << " width=\"" + videoWidth + "\" contentwidth=\"" + videoWidth + "\""
              end
              if !videoHeight.nil?
                replace << " depth=\"" + videoHeight + "\" contentdepth=\"" + videoHeight + "\""
              end
              replace << " />\n"
              replace << "\t</videoobject>\n"
              replace << "</mediaobject>\n"
              replace << "++++\n"
              contents.gsub!(search, replace)
            end
            f = File.open(toPath, "wb")
            f.write(contents)
            f.close
          else
            FileUtils.cp(fromPath, toPath)
          end
        end
      end
    end
  end
  print "done.\n"

  print "  - Generating DocBook... "
  docbook = Asciidoctor.convert_file("tmp/adoc/" + which + ".adoc", :to_file => false, :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :backend => "docbook", :attributes => {"numbered" => true})
  f = File.open("tmp/" + which + "-docbook.xml", "wb")
  f.write(docbook)
  f.close
  print "done.\n"

  print "  - Generating chunked html... "
  FileUtils.rm_rf("output/" + which)
  Dir.mkdir("output/" + which) unless Dir.exists?("output/" + which)
  rc=system("java com.icl.saxon.StyleSheet tmp/" + which + "-docbook.xml lib/html-chunked-parameters.xsl base.dir=output/" + which + " highlight.xslthl.config=file:///" + $rootDir + "/lib/xslthl/highlighters/xslthl-config.xml")
  if rc.nil?
    raise "saxon failed (be sure to have Java)!"
  end
  if rc == false
    raise "saxon failed!"
  end
  print "done.\n"
end


def main
  initialDir = Dir.pwd
  Dir.chdir($rootDir)
  begin
    $stdout.sync = true
    Dir.mkdir("tmp") unless Dir.exists?("tmp")
    Dir.mkdir("output") unless Dir.exists?("output")
    process("developers")
    #process("editors")
  ensure
    Dir.chdir(initialDir)
  end
end

main
