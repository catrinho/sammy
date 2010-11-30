# jsdoc.rb (by quirkey/Aaron Quint)
#
# Simple Documentation generator for JavaScript Class files.
#
# usage :
# ruby jsdoc.rb FILE
#
# looks for files formatted like
#
# MyClass = Class.extend({
#   ...
#   // My method does this
#   // with multi line comments
#   myMethod: function(arg1, arg2) {
#     ...
#   },
#
#   _noDoc: function() {
#     ...
#   }
#
# });

require 'rubygems'
require 'haml'
require 'rdiscount'
require 'active_support/ordered_hash'
require 'active_support/core_ext/hash'
require 'yajl'

class JSDoc

  KLASS_REGEXP     = /^\s*([A-Z][\w\d\.]+)\s+=\s+function\s*\(([^\)]+)?\)/
  FUNCTION_REGEXP  = /(\/\/(.*)|(([\w\d_\$]+)\:\s*function\s*\(([\w\d\s,]+)?\))|(function\s+([\w\d_\$]+)\(([\w\d\s,]+)?\)))/im
  ATTRIBUTE_REGEXP = /^\s+([\w\d_\$]+)\:\s+(.*)\,\s+/i

  TEMPLATE_DIR = File.expand_path(File.join(File.dirname(__FILE__), 'templates'))

  def initialize(base_path, *paths)
    @base_path = File.expand_path(base_path)
    @paths = []
    paths.flatten.each do |path|
      path = File.expand_path(path)
      if File.directory?(path)
        Dir[path + '/*.js'].each do |p|
          @paths << p
        end
      else
        @paths << path
      end
    end
    @docs = {}
  end

  def parse!
    @paths.each do |path|
      @docs.deep_merge!(parse_file(path))
    end
    sort_docs
  end

  def parse_file(filename)
    puts "parsing #{filename}"
    file = File.open(filename)

    klass   = {:klass => 'Top Level'}
    klass_name = ""
    context = nil
    current = nil
    comment = ""
    docs    = ActiveSupport::OrderedHash.new({})
    relative_filename = filename.gsub(@base_path, '')
    file.each do |line|
      if klass_match = line.match(KLASS_REGEXP)
        klass_name = klass_match[1].to_s.strip;
        klass = {
          :name => klass_name,
          :args => klass_match[2].to_s.split(',').collect {|a| a.strip },
          :doc => "",
          :filename => relative_filename,
          :lineno => file.lineno,
          :methods => [],
          :attributes => []
        }
        if context == :comment
          klass[:doc] = convert_doc(comment)
          comment = ""
        end
        docs[klass_name] = klass
      else
        if line_match = line.match(FUNCTION_REGEXP)
          current = ((line_match[0] =~ /^\/\//) ? :comment : :method)
          if current == :comment
            this_comment = line_match[2].to_s
            if context == :comment
              comment << this_comment
            else
              comment = this_comment
            end
          elsif current == :method
            name = line_match[4].to_s
            args = line_match[5].to_s.split(',').collect {|a| a.strip }
            if !(name.nil? || name.strip == '')
              meth = {
                :name => name,
                :args => args,
                :filename => relative_filename,
                :lineno => file.lineno
              }
              if context == :comment
                if !(comment.nil? || comment.strip == '')
                  meth[:doc] = convert_doc(comment)
                  comment = ""
                  docs[klass_name][:methods] << meth if docs[klass_name] && docs[klass_name][:methods]
                end
              end
            end
          end
        elsif line_match = line.match(ATTRIBUTE_REGEXP)
          current = :attribute
          attribute = {
            :name  => line_match[1].to_s,
            :default => line_match[2].to_s,
            :filename => relative_filename,
            :lineno   => file.lineno
          }
          if context == :comment
            if !(comment.nil? || comment.strip == '')
              attribute[:doc] = convert_doc(comment)
              comment = ""
              docs[klass_name][:attributes] << attribute if docs[klass_name] && docs[klass_name][:attributes]
            end
          end
        else
          current = nil
        end
        context = current
      end
    end
    file.close
    docs
  end

  def sort_docs
    # sort the methods and attributes for each klass
    @docs.each do |klass, klass_methods|
      @docs[klass][:attributes] = klass_methods[:attributes].sort {|a,b| a[:name] <=> b[:name] }
      @docs[klass][:methods] = klass_methods[:methods].sort {|a,b| a[:name] <=> b[:name] }
    end

    @docs = @docs.reject do |klass, klass_methods|
      # get rid of undocumented classes
      klass_methods[:doc].nil? || klass_methods[:doc].to_s.strip == ''
    end.sort {|a, b|
      a[1][:name] <=> b[1][:name]
    }
  end

  def convert_doc(text)
    final_text = ""
    text.strip.each_line do |l|
      final_text << l.gsub(/^\ #/,'#')
    end
    final_text = RDiscount.new(final_text).to_html
    final_text.gsub!(/<pre><code>/m, '<pre class="prettyprint"><code>')
    final_text
  end

  def docs
    parse! if !@docs
    @docs
  end

  def to_haml
    rendered = {}
    # build menu
    menu_template = load_template('menu')
    rendered['menu.html'] = Haml::Engine.new(menu_template).to_html(Object.new, :docs => docs)

    rendered
  end

  def to_json
    Yajl::Encoder.encode(@docs, :pretty => true)
  end

private

  def load_template(name)
    File.read(File.join(TEMPLATE_DIR, "#{name}.haml"))
  end
end


# rdoc = RDoc::Markup::ToHtml.new

if __FILE__ == $0
  puts "Running JSDOC on #{ARGV}"
  jsdoc = JSDoc.new(Dir.pwd, *ARGV)
  jsdoc.parse!
  puts jsdoc.to_haml
  #puts jsdoc.to_json
end
