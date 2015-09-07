<?xml version='1.0'?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:import href="docbook-xsl/html/chunk.xsl" />
  <xsl:import href="docbook-xsl/html/highlight.xsl" />
  <!-- See http://docbook.sourceforge.net/release/xsl/1.78.1/doc/html/index.html -->
  <xsl:param name="chunker.output.encoding" select="'UTF-8'" />
  <xsl:param name="highlight.source" select="1" />
  <xsl:param name="chunk.quietly" select="1" />
  <xsl:param name="chunk.tocs.and.lots" select="1" />
  <xsl:param name="toc.list.type" select="'ul'" />
  <xsl:param name="generate.toc" select="'
appendix          nop
article           nop
book              toc
chapter           nop
part              nop
preface           nop
qandadiv          nop
qandaset          nop
reference         nop
sect1             nop
sect2             nop
sect3             nop
sect4             nop
sect5             nop
section           nop
set               nop
  '" />
</xsl:stylesheet>
