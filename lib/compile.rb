require "fileutils"
require "asciidoctor"
require "asciidoctor-pdf"
require "asciidoctor-epub3"
require "nokogiri"

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

# Implement our custom render of YouTube videos (asciidoctor-pdf simply strips them out)
module Asciidoctor
  module Pdf
    class Converter
      def convert_video(node)
        videoID = node.attr 'target'
        url = "https://www.youtube.com/watch?v=" + videoID
        layout_prose 'Watch video on YouTube at <a href="' + url + '">' + url + '</a>';
      end
    end
  end
end

$rootDir = File.expand_path(File.dirname(File.dirname(__FILE__)))

def process(which)
  print "### BUILDING " + which + " ### \n"

  print "Generating PDF (this takes a while)... "
  File.delete("output/" + which + ".pdf") if File.exist?("output/" + which + ".pdf")
  Asciidoctor.convert_file(which + ".adoc", :to_file => "output/" + which + ".pdf", :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :backend => "pdf", :attributes => {"numbered" => true})
  print "done.\n"

  print "Optimizing PDF... "
  File.delete("output/" + which + "-optimized.pdf") if File.exist?("output/" + which + "-optimized.pdf")
  # Let's look for GhostScript
  gs = nil
  for checkGS in ['gs', 'gswin64c.exe', 'gswin32c.exe']
    begin
      rc = `#{checkGS} --version`
    rescue
      rc = nil
    end
    if !rc.nil?
      gs = checkGS
      break
    end
  end
  if gs.nil?
    print "SKIPPED (GhostScript executable not found)\n"
  else
    # GhostScript found: let's optimize the PDF
    sizeFrom = File.size("output/" + which + ".pdf")
    begin
      rc = `#{gs} -q -dNOPAUSE -dBATCH -dSAFER -dNOOUTERSAVE -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -dCannotEmbedFontPolicy=/Warning -dDownsampleColorImages=true -dColorImageResolution=300 -dDownsampleGrayImages=true -dGrayImageResolution=300 -dDownsampleMonoImages=true -dMonoImageResolution=300 -sOutputFile=output/#{which}-optimized.pdf output/#{which}.pdf output/#{which}.pdfmarks`
    end
    if !File.exist?("output/" + which + "-optimized.pdf")
      print "GhostScript FAILED\n"
    else
      sizeTo = File.size("output/" + which + "-optimized.pdf")
      File.delete("output/" + which + ".pdf")
      File.rename("output/" + which + "-optimized.pdf", "output/" + which + ".pdf")
      print "done (size changed from #{format("%.1f", sizeFrom / 1024.0)} to #{format("%.1f", sizeTo / 1024.0)} KB).\n"
    end
  end
  File.delete("output/" + which + ".pdfmarks") if File.exist?("output/" + which + ".pdfmarks")

  print "Generating EPUB... "
  stdOutString = StringIO.new
  stdOutOriginal = $stdout
  $stdout = stdOutString
  begin
    Asciidoctor.convert_file(which + ".adoc", :to_file => "output/" + which + ".epub", :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :backend => "epub3", :attributes => {"numbered" => true})
  ensure
    $stdout = stdOutOriginal
  end
  print "done.\n"

  print "Generating single-page HTML... "
  adoc = Asciidoctor.convert_file(which + ".adoc", :to_file => false, :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :attributes => {"numbered" => true})
  adoc.gsub!('src="//www.youtube.com/', 'src="https://www.youtube.com/')
  f = File.open("output/" + which + ".html", "wb")
  f.write(adoc)
  f.close
  print "done.\n"

  print "Preparing AsciiDoc files for DocBook... "
  Dir.mkdir("tmp/adoc") unless Dir.exists?("tmp/adoc")
  FileUtils.cp(which + ".adoc", "tmp/adoc/" + which + ".adoc")
  FileUtils.rm_rf("tmp/adoc/" + which)
  for step in 1..2
    # In first step we create the directory tree, in second step we copy the files
    Dir.glob(which + "/**/*").each do |fromPath|
      toPath = fromPath.sub(which + "/", "tmp/adoc/" + which + "/")
      if File.directory?(fromPath)
        if step == 1
          FileUtils.mkdir_p(toPath) unless Dir.exists?(toPath)
        end
      else
        if step == 2
          if /\.adoc$/ =~ toPath
            # Let's hack the AsciiDoc file
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
            # Write out the hacked AsciiDoc file
            f = File.open(toPath, "wb")
            f.write(contents)
            f.close
          else
            # It's not a file that ends with .adoc: simply copy it
            FileUtils.cp(fromPath, toPath)
          end
        end
      end
    end
  end
  print "done.\n"

  print "Generating DocBook file... "
  docbook = Asciidoctor.convert_file("tmp/adoc/" + which + ".adoc", :to_file => false, :header_footer => true, :safe => Asciidoctor::SafeMode::UNSAFE, :backend => "docbook", :attributes => {"numbered" => true})
  f = File.open("tmp/" + which + "-docbook.xml", "wb")
  f.write(docbook)
  f.close
  print "done.\n"

  print "Generating dirty multi-page HTML... "
  now = DateTime.now.strftime("%F %T %z")
  FileUtils.rm_rf("tmp/html/" + which)
  Dir.mkdir("tmp/html") unless Dir.exists?("tmp/html")
  Dir.mkdir("tmp/html/" + which)
  rc=system("java com.icl.saxon.StyleSheet tmp/" + which + "-docbook.xml lib/html-chunked-parameters.xsl base.dir=tmp/html/" + which + " highlight.xslthl.config=file:///" + $rootDir + "/lib/xslthl/highlighters/xslthl-config.xml")
  if rc.nil?
    raise "saxon failed (be sure to have Java)!"
  end
  if rc == false
    raise "saxon failed!"
  end
  print "done.\n"

  print "Generating final multi-page HTML... "
  templates = {}
  FileUtils.rm_rf("output/" + which)
  Dir.mkdir("output/" + which)
  f = File.open("tmp/html/" + which + "/bk01-toc.html", "rb")
  contents = f.read
  f.close
  toc = Nokogiri::HTML(contents).css("div.toc")[0].inner_html
  subLen = ("tmp/html/" + which + "/").length
  Dir["tmp/html/" + which + "/**/*.html"].each do |fromPath|
    relName = fromPath[subLen..-1]
    templateKey = 'default.html'
    if File.exist?("lib/html_chunked/" + relName)
      templateKey = relName
    end
    if templates[templateKey].nil?
      f = File.open("lib/html_chunked/" + templateKey)
      templates[templateKey] = f.read
      f.close
    end
    if relName == "bk01-toc.html"
      next
    end
    toPath = "output/" + which + "/" + relName
    subDirs = relName.split("/")[0..-1]
    subDirs.pop
    if subDirs.length == 0
      thisToc = toc
    else
      dirName = "output/" + which
      subDirs.each do |subDir|
        dirName << "/" + subDir
        Dir.mkdir(dirName) unless Dir.exists?(dirName)
      end
      depthPath = ''
      (1..subDirs.length).each do |i|
        depthPath << '../'
      end
      thisToc = toc.gsub(' href="', ' href="' + depthPath)
    end
    f = File.open("tmp/html/" + which + "/" + relName, "rb")
    contents = f.read
    f.close
    doc = Nokogiri::HTML(contents)
    docTitle = doc.css("title")[0].inner_html.gsub("&nbsp;", " ")
    bodyHTML = ''
    doc.css("body")[0].children.each do |node|
      if node.type == Nokogiri::XML::Node::ELEMENT_NODE && node.name == 'div' && (node['class'] == 'navheader' || node['class'] == 'navfooter')
        next
      end
      bodyHTML << node.to_html
    end
    wonderfulHTML = templates[templateKey].gsub('[[TITLE]]', docTitle).gsub('[[TOC]]', thisToc).gsub('[[DATETIME]]', now).gsub('[[BODY]]', bodyHTML)
    f = File.open("output/" + which + "/" + relName, "wb")
    f.write(wonderfulHTML)
    f.close
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
