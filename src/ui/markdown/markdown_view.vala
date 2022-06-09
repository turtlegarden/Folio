
public class GtkMarkdown.View : GtkSource.View {

    public bool dark { get; set; default = false; }
    public Gdk.RGBA theme_color { get; set; }

    public Gdk.RGBA h6_color {
        get {
            var rgba = get_style_context ().get_color ();
            rgba.alpha = 0.6f;
            return rgba;
        }
    }

    public Gdk.RGBA marking_color {
        get {
            var rgba = get_style_context ().get_color ();
            rgba.alpha = 0.6f;
            return rgba;
        }
    }

    public Gdk.RGBA url_color {
        get {
            var hsl = Color.rgb_to_hsl (Color.RGBA_to_rgb (theme_color));
            hsl.l = 0.42f;
            return Color.rgb_to_RGBA (Color.hsl_to_rgb (hsl));
        }
    }

    public Gdk.RGBA highlight_color {
        get {
            var rgb = Color.RGBA_to_rgb (theme_color);
            if (dark) {
                var hsl = Color.rgb_to_hsl (rgb);
                hsl.s = float.min (hsl.s * 2.2f, 1);
                hsl.l = 0.5f;
                var rgba = Color.rgb_to_RGBA (Color.hsl_to_rgb (hsl));
                rgba.alpha = 0.5f;
                return rgba;
            } else {
                rgb.r = float.min (rgb.r * 1.8f, 1);
                rgb.g = float.min (rgb.g * 2.0f, 1);
                rgb.b = float.min (rgb.b * 1.4f, 1);
                var hsl = Color.rgb_to_hsl (rgb);
                hsl.l = 0.82f;
                return Color.rgb_to_RGBA (Color.hsl_to_rgb (hsl));
            }
        }
    }

    public Gdk.RGBA tinted_foreground {
        get {
            var hsl = Color.rgb_to_hsl (Color.RGBA_to_rgb (theme_color));
            hsl.l = 0.5f;
            hsl.s *= 0.64f;
            return Color.rgb_to_RGBA (Color.hsl_to_rgb (hsl));
        }
    }

    public Gdk.RGBA block_color {
        get {
            var hsl = Color.rgb_to_hsl (Color.RGBA_to_rgb (theme_color));
            hsl.l = dark ? 0.7f : 0.3f;
            hsl.s *= 0.64f;
            var rgba = Color.rgb_to_RGBA (Color.hsl_to_rgb (hsl));
            rgba.alpha = 0.1f;
            return rgba;
        }
    }

    public bool show_gutter { get; set; default = true; }

    public new Gtk.TextBuffer? buffer {
        get { return base.buffer; }
        set {
            base.buffer = value;
            update_color_scheme ();
        }
    }

	public uint get_title_level (uint line) {
        Gtk.TextIter start;
        Gtk.TextIter end;
        buffer.get_iter_at_line (out start, (int) line);
        buffer.get_iter_at_line (out end, (int) line + 1);
        var str = start.get_text (end);
        var i = 0;
        while (i < 6 && i < str.length) {
            if (str[i] != '#') break;
            i++;
        }
        if (str[i] != ' ') return 0;
        return i;
	}

	public void set_title_level (uint line, uint level) {
        var old_title_level = get_title_level (line);
        if (old_title_level == level) return;
        if (level > old_title_level) {
            if (old_title_level == 0) {
                Gtk.TextIter start;
                buffer.get_iter_at_line (out start, (int) line);
                var end = start.copy ();
                end.forward_chars (1);
                var str = start.get_text (end);
                if (str[0] != ' ') {
                    buffer.insert (ref start, " ", 1);
                }
            }
            Gtk.TextIter start;
            buffer.get_iter_at_line (out start, (int) line);
            var str = string.nfill(level - old_title_level, '#');
            buffer.insert (ref start, str, str.length);
        } else {
            Gtk.TextIter start;
            buffer.get_iter_at_line (out start, (int) line);
            var end = start.copy ();
            end.forward_chars ((int) (old_title_level - level));
            buffer.@delete (ref start, ref end);
            if (level == 0) {
                var e = end.copy ();
                e.forward_chars (1);
                var str = end.get_text (e);
                if (str[0] == ' ') {
                    buffer.@delete (ref end, ref e);
                }
            }
        }
	}

    private GtkSource.GutterRendererText renderer;

	private Regex is_link;
	private Regex is_escape;
	private Regex is_blockquote;

	private Regex is_horizontal_rule;

	private Regex is_bold_0;
	private Regex is_bold_1;
	private Regex is_italic_0;
	private Regex is_italic_1;
	private Regex is_strikethrough_0;
	private Regex is_strikethrough_1;
	private Regex is_highlight;

	private Regex is_code_span;
	private Regex is_code_block;

    construct {
        try {
            var f = RegexCompileFlags.OPTIMIZE | RegexCompileFlags.CASELESS;
	        is_link = new Regex ("\\[([^\\[]+?)\\](\\([^\\)\\n]+?\\))", f, 0);
	        is_escape = new Regex ("\\\\[\\\\`*_{}\\[\\]()#+-.!]", f, 0);

	        /*
             * Example:
             * > Quoted text.
             * > Quoted text with `code span`.
             * >> Blockquote **nested**.
             */
	        is_blockquote = new Regex ("^( {0,3}>( {0,4}>)*).*", f | RegexCompileFlags.MULTILINE, 0);

	        is_horizontal_rule = new Regex ("^[ ]{0,3}((-[ ]{0,2}){3,}|(_[ ]{0,2}){3,}|(\\*[ ]{0,2}){3,})[ \\t]*$", f | RegexCompileFlags.MULTILINE, 0);

            /*
             * Examples:
             * Lorem *ipsum dolor* sit amet.
             * Here's an *emphasized text containing an asterisk (\*)*.
             */
	        is_italic_0 = new Regex ("((?<!\\*)\\*)([^\\* \\t].*?(?<!\\\\|\\*| |\\t))(\\*(?!\\*))", f, 0);

            /*
             * Examples:
             * Lorem _ipsum dolor_ sit amet.
             * Here's an _emphasized text containing an underscore (\_)_.
             */
	        is_italic_1 = new Regex ("((?<!_)_)([^_ \\t].*?(?<!\\\\|_| |\\t))(_(?!_))", f, 0);

            /*
             * Examples:
             * Lorem **ipsum dolor** sit amet.
             * Here's a **strongly emphasized text containing an asterisk (\*).**
             */
	        is_bold_0 = new Regex ("(\\*\\*)([^\\* \\t].*?(?<!\\\\|\\*| |\\t))(\\*\\*)", f, 0);

            /*
             * Examples:
             * Lorem __ipsum dolor__ sit amet.
             * Here's a __strongly emphasized text containing an underscore (\_)__.
             */
	        is_bold_1 = new Regex ("(__)([^_ \\t].*?(?<!\\\\|_| |\\t))(__)", f, 0);

	        is_strikethrough_0 = new Regex ("((?<!\\~)\\~)([^\\~ \\t].*?(?<!\\\\|\\~| |\\t))(\\~(?!\\~))", f, 0);
	        is_strikethrough_1 = new Regex ("(~~)([^~ \\t].*?(?<!\\\\|~| |\\t))(~~)", f, 0);
	        is_highlight = new Regex ("(\\=\\=)([^\\= \\t].*?(?<!\\\\|\\=| |\\t))(\\=\\=)", f, 0);

	        is_code_span = new Regex ("(?<!`)(`)([^`]+(?:`{2,}[^`]+)*)(`)(?!`)", RegexCompileFlags.OPTIMIZE | RegexCompileFlags.CASELESS | RegexCompileFlags.MULTILINE, 0);
	        is_code_block = new Regex ("(?<![^\\n])(```[^`\\n]*)\\n([^`]*)(```)(?=\\n)", f, 0);
	    } catch (RegexError e) {
	        error (e.message);
	    }

        notify["dark"].connect ((s, p) => update_color_scheme ());
        notify["theme-color"].connect ((s, p) => update_color_scheme ());
        update_color_scheme ();

        {
            var gutter = get_gutter (Gtk.TextWindowType.LEFT);
            renderer = new GtkSource.GutterRendererText ();
            renderer.xalign = 0.5f;
            renderer.yalign = 0.5f;
            renderer.query_data.connect ((lines, line) => {
                var title_level = get_title_level (line);
                if (title_level != 0 && show_gutter) {
                    renderer.text = @"H$title_level";
                } else {
                    renderer.text = null;
                }
            });
            renderer.query_activatable.connect ((iter, area) => true);
            renderer.activate.connect ((iter, area, button, state, n_presses) => {
                if (button != 1) return;
                var line = iter.get_line ();
                var title_level = get_title_level (line);
                if (title_level == 0) return;
                var popover = new HeadingPopover(this, line);
                popover.autohide = true;
                popover.has_arrow = true;
                popover.position = Gtk.PositionType.LEFT;
                popover.set_parent (this);
                popover.pointing_to = area;
                popover.popup ();
            });
            gutter.insert (renderer, 0);
        }
    }


    private Gtk.TextTag[] text_tags_title;

    private Gtk.TextTag text_tag_url;
    private Gtk.TextTag text_tag_escaped;
    private Gtk.TextTag text_tag_blockquote;
    private Gtk.TextTag text_tag_blockquote_marker;

    private Gtk.TextTag text_tag_horizontal_rule;

    private Gtk.TextTag text_tag_bold;
    private Gtk.TextTag text_tag_italic;
    private Gtk.TextTag text_tag_strikethrough;
    private Gtk.TextTag text_tag_highlight;

    private Gtk.TextTag text_tag_code_span;
    private Gtk.TextTag text_tag_code_block;
    private Gtk.TextTag text_tag_around;

    private Gtk.TextTag text_tag_hidden;
    private Gtk.TextTag text_tag_invisible;

	private void update_color_scheme () {
        if (buffer is GtkSource.Buffer) {
            var buffer = buffer as GtkSource.Buffer;
            buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "paper-dark" : "paper");

            var block_color = block_color;
            var tinted_foreground = tinted_foreground;

            update_title_styling ();

            text_tag_url = get_or_create_tag ("markdown-link");
            text_tag_url.foreground_rgba = url_color;
            text_tag_url.underline = Pango.Underline.SINGLE;

            text_tag_escaped = get_or_create_tag ("markdown-escaped-char");
            text_tag_escaped.foreground_rgba = tinted_foreground;

            text_tag_blockquote = get_or_create_tag ("markdown-blockquote");
            text_tag_blockquote.paragraph_background_rgba = block_color;
            text_tag_blockquote.line_height = 2;

            text_tag_blockquote_marker = get_or_create_tag ("markdown-blockquote-marker");
            text_tag_blockquote_marker.background_rgba = tinted_foreground;
            text_tag_blockquote_marker.foreground_rgba = tinted_foreground;
            text_tag_blockquote_marker.size_points = 8;

            text_tag_horizontal_rule = get_or_create_tag ("markdown-horizontal-rule");
            text_tag_horizontal_rule.justification = Gtk.Justification.CENTER;
            text_tag_horizontal_rule.foreground_rgba = marking_color;


            text_tag_bold = get_or_create_tag ("markdown-bold");
            text_tag_bold.weight = 700;

            text_tag_italic = get_or_create_tag ("markdown-italic");
            text_tag_italic.style = Pango.Style.ITALIC;

            text_tag_strikethrough = get_or_create_tag ("markdown-strikethrough");
            text_tag_strikethrough.strikethrough = true;

            text_tag_highlight = get_or_create_tag ("markdown-highlight");
            text_tag_highlight.background_rgba = highlight_color;


            text_tag_around = get_or_create_tag ("markdown-code-block-around");
            text_tag_around.family = "Monospace";
            text_tag_around.scale = 0.7;
            var around_block_color = block_color;
            around_block_color.alpha = 0.8f;
            text_tag_around.foreground_rgba = around_block_color;


            text_tag_code_span = get_or_create_tag ("markdown-code-span");
            text_tag_code_span.family = "Monospace";
            text_tag_code_span.background_rgba = block_color;

            text_tag_code_block = get_or_create_tag ("markdown-code-block");
            text_tag_code_block.family = "Monospace";
            text_tag_code_block.indent = 16;


            text_tag_hidden = get_or_create_tag ("hidden-character");
            text_tag_hidden.invisible = true;

            text_tag_invisible = get_or_create_tag ("invisible-character");
            text_tag_invisible.foreground = "rgba(0,0,0,0.001)";

            buffer.changed.connect (restyle_text);
            buffer.notify["cursor-position"].connect (restyle_text);
            restyle_text();
        }
	}

	private float interpolate (float x) {
	    return 1 - (float) Math.sqrt (1 - x);
	}

	private void update_title_styling () {
	    var tags = new Gtk.TextTag[6];
        var last_i = tags.length - 1;
	    for (var i = 0; i < tags.length; i++) {
	        var tag = get_or_create_tag (@"markdown-h$i");
	        var bold_f = (last_i - int.min (i, last_i - 1) - 1) / (float) last_i;
            tag.weight = 600 + (int) (bold_f * 300);
            var scale_f = (last_i - i) / (float) last_i;
            tag.scale = 1.0f + interpolate(scale_f) * 1.4f;
            if (i == last_i)
                tag.foreground_rgba = h6_color;
	        tags[i] = tag;
	    }
	    text_tags_title = tags;
	}

	private Gtk.TextTag get_or_create_tag (string name) {
	    return buffer.tag_table.lookup (name) ?? buffer.create_tag (name);
	}

	private void remove_tags (Gtk.TextIter start, Gtk.TextIter end) {
	    buffer.remove_tag (text_tag_hidden, start, end);
        buffer.remove_tag (text_tag_invisible, start, end);
        buffer.remove_tag (text_tag_url, start, end);
        buffer.remove_tag (text_tag_escaped, start, end);
        buffer.remove_tag (text_tag_code_span, start, end);
        buffer.remove_tag (text_tag_code_block, start, end);
        buffer.remove_tag (text_tag_around, start, end);
        buffer.remove_tag (text_tag_bold, start, end);
        buffer.remove_tag (text_tag_italic, start, end);
        buffer.remove_tag (text_tag_strikethrough, start, end);
        buffer.remove_tag (text_tag_highlight, start, end);
        buffer.remove_tag (text_tag_blockquote, start, end);
        foreach (var t in text_tags_title)
            buffer.remove_tag (t, start, end);
	}

	private void restyle_text () {
        renderer.queue_draw ();
        Gtk.TextIter buffer_start, buffer_end, cursor_location;
        buffer.get_bounds (out buffer_start, out buffer_end);
        remove_tags (buffer_start, buffer_end);
        var cursor = buffer.get_insert ();
        buffer.get_iter_at_mark (out cursor_location, cursor);
        string buffer_text = buffer.get_text (buffer_start, buffer_end, true);

        {
            var lines = buffer.get_line_count ();
            for (var line = 0; line < lines; line++) {
                var title_level = get_title_level (line);
                if (title_level != 0) {
                    Gtk.TextIter start, end;
                    buffer.get_iter_at_line (out start, line);
                    end = start.copy ();
                    end.forward_chars ((int) title_level + 1);
                    buffer.apply_tag (text_tag_hidden, start, end);
                    buffer.get_iter_at_line (out start, line + 1);
                    buffer.apply_tag (text_tags_title[title_level - 1], end, start);
                }
            }
        }

        try {
            MatchInfo matches;

            format_horizontal_rule (buffer_text, out matches);

            format_blockquote (buffer_text, out matches);

            // Check for links
            if (is_link.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
                do {
                    int start_text_pos, end_text_pos;
                    int start_url_pos, end_url_pos;
                    bool have_text = matches.fetch_pos (1, out start_text_pos, out end_text_pos);
                    bool have_url = matches.fetch_pos (2, out start_url_pos, out end_url_pos);

                    if (have_text && have_url) {
                        start_text_pos = buffer_text.char_count ((ssize_t) start_text_pos);
                        end_text_pos = buffer_text.char_count ((ssize_t) end_text_pos);
                        start_url_pos = buffer_text.char_count ((ssize_t) start_url_pos);
                        end_url_pos = buffer_text.char_count ((ssize_t) end_url_pos);

                        // Convert the character offsets to TextIter's
                        Gtk.TextIter start_text_iter, end_text_iter, start_url_iter, end_url_iter;
                        buffer.get_iter_at_offset (out start_text_iter, start_text_pos);
                        buffer.get_iter_at_offset (out end_text_iter, end_text_pos);
                        buffer.get_iter_at_offset (out start_url_iter, start_url_pos);
                        buffer.get_iter_at_offset (out end_url_iter, end_url_pos);

                        // Skip if our cursor is inside the URL text
                        if (cursor_location.in_range (start_text_iter, end_url_iter)) {
                            continue;
                        }

                        var start_bracket_iter = start_text_iter.copy ();
                        start_bracket_iter.backward_char ();
                        var end_bracket_iter = end_text_iter.copy ();
                        end_bracket_iter.forward_char ();

                        // Apply our styling
                        buffer.apply_tag (text_tag_url, start_text_iter, end_text_iter);
                        buffer.apply_tag (text_tag_hidden, start_url_iter, end_url_iter);
                        buffer.apply_tag (text_tag_hidden, start_bracket_iter, start_text_iter);
                        buffer.apply_tag (text_tag_hidden, end_text_iter, end_bracket_iter);
                    }
                } while (matches.next ());
            }

            // Check for formatting
            do_formatting_pass (is_bold_0, text_tag_bold, buffer_text, cursor_location, out matches);
            do_formatting_pass (is_bold_1, text_tag_bold, buffer_text, cursor_location, out matches);
            do_formatting_pass (is_italic_0, text_tag_italic, buffer_text, cursor_location, out matches);
            do_formatting_pass (is_italic_1, text_tag_italic, buffer_text, cursor_location, out matches);
            do_formatting_pass (is_strikethrough_0, text_tag_strikethrough, buffer_text, cursor_location, out matches);
            do_formatting_pass (is_strikethrough_1, text_tag_strikethrough, buffer_text, cursor_location, out matches);
            do_formatting_pass (is_highlight, text_tag_highlight, buffer_text, cursor_location, out matches);

            format_escape (buffer_text, cursor_location, out matches);
            format_code_span (buffer_text, cursor_location, out matches);
            format_code_block (buffer_text, cursor_location, out matches);
        } catch (RegexError e) {}
    }

    void format_horizontal_rule (
        string buffer_text,
        out MatchInfo matches
    ) throws RegexError {
        // Check for code blocks
        if (is_horizontal_rule.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
            do {
                int start_pos, end_pos;
                bool have = matches.fetch_pos (0, out start_pos, out end_pos);

                if (have) {
                    start_pos = buffer_text.char_count ((ssize_t) start_pos);
                    end_pos = buffer_text.char_count ((ssize_t) end_pos);

                    // Convert the character offsets to TextIter's
                    Gtk.TextIter start_iter,   end_iter;
                    buffer.get_iter_at_offset (out start_iter, start_pos);
                    buffer.get_iter_at_offset (out end_iter, end_pos);

                    // Apply styling
                    buffer.apply_tag (text_tag_horizontal_rule, start_iter, end_iter);
                }
            } while (matches.next ());
        }
    }

    void format_blockquote (
        string buffer_text,
        out MatchInfo matches
    ) throws RegexError {
        // Check for code blocks
        if (is_blockquote.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
            do {
                int start_marker_pos, end_marker_pos;
                int start_full_pos,   end_full_pos;
                bool have_marker = matches.fetch_pos (1, out start_marker_pos, out end_marker_pos);
                bool have_full = matches.fetch_pos (0, out start_full_pos, out end_full_pos);

                if (have_marker && have_full) {
                    start_marker_pos = buffer_text.char_count ((ssize_t) start_marker_pos);
                    end_marker_pos = buffer_text.char_count ((ssize_t) end_marker_pos);
                    start_full_pos = buffer_text.char_count ((ssize_t) start_full_pos);
                    end_full_pos = buffer_text.char_count ((ssize_t) end_full_pos);

                    // Convert the character offsets to TextIter's
                    Gtk.TextIter start_marker_iter, end_marker_iter;
                    Gtk.TextIter start_full_iter,   end_full_iter;
                    buffer.get_iter_at_offset (out start_marker_iter, start_marker_pos);
                    buffer.get_iter_at_offset (out end_marker_iter, end_marker_pos);
                    buffer.get_iter_at_offset (out start_full_iter, start_full_pos);
                    buffer.get_iter_at_offset (out end_full_iter, end_full_pos);

                    // Apply styling
                    buffer.apply_tag (text_tag_blockquote, start_full_iter, end_full_iter);
                    buffer.apply_tag (text_tag_blockquote_marker, start_marker_iter, end_marker_iter);
                }
            } while (matches.next ());
        }
    }

    void format_code_block (
        string buffer_text,
        Gtk.TextIter cursor_location,
        out MatchInfo matches
    ) throws RegexError {
        // Check for code blocks
        if (is_code_block.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
            do {
                int start_before_pos, end_before_pos;
                int start_code_pos,   end_code_pos;
                int start_after_pos,  end_after_pos;
                bool have_code_start = matches.fetch_pos (1, out start_before_pos, out end_before_pos);
                bool have_code = matches.fetch_pos (2, out start_code_pos, out end_code_pos);
                bool have_code_close = matches.fetch_pos (3, out start_after_pos, out end_after_pos);

                if (have_code_start && have_code && have_code_close) {
                    start_before_pos = buffer_text.char_count ((ssize_t) start_before_pos);
                    end_before_pos = buffer_text.char_count ((ssize_t) end_before_pos);
                    start_code_pos = buffer_text.char_count ((ssize_t) start_code_pos);
                    end_code_pos = buffer_text.char_count ((ssize_t) end_code_pos);
                    start_after_pos = buffer_text.char_count ((ssize_t) start_after_pos);
                    end_after_pos = buffer_text.char_count ((ssize_t) end_after_pos);

                    // Convert the character offsets to TextIter's
                    Gtk.TextIter start_before_iter, end_before_iter;
                    Gtk.TextIter start_code_iter,   end_code_iter;
                    Gtk.TextIter start_after_iter,  end_after_iter;
                    buffer.get_iter_at_offset (out start_before_iter, start_before_pos);
                    buffer.get_iter_at_offset (out end_before_iter, end_before_pos);
                    buffer.get_iter_at_offset (out start_code_iter, start_code_pos);
                    buffer.get_iter_at_offset (out end_code_iter, end_code_pos);
                    buffer.get_iter_at_offset (out start_after_iter, start_after_pos);
                    buffer.get_iter_at_offset (out end_after_iter, end_after_pos);

                    // Apply styling
                    remove_tags (start_before_iter, end_after_iter);

                    buffer.apply_tag (text_tag_code_block, start_code_iter, end_code_iter);
                    buffer.apply_tag (text_tag_around, start_before_iter, end_before_iter);
                    buffer.apply_tag (text_tag_around, start_after_iter, end_after_iter);

                    // Skip if our cursor is inside the code
                    if (cursor_location.in_range (start_before_iter, end_after_iter)) {
                        continue;
                    }

                    buffer.apply_tag (text_tag_invisible, start_before_iter, end_before_iter);
                    buffer.apply_tag (text_tag_invisible, start_after_iter, end_after_iter);

                }
            } while (matches.next ());
        }
    }

    void format_code_span (
        string buffer_text,
        Gtk.TextIter cursor_location,
        out MatchInfo matches
    ) throws RegexError {
        if (is_code_span.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
            do {
                int start_before_pos, end_before_pos;
                int start_code_pos,   end_code_pos;
                int start_after_pos,  end_after_pos;
                bool have_code_start = matches.fetch_pos (1, out start_before_pos, out end_before_pos);
                bool have_code = matches.fetch_pos (2, out start_code_pos, out end_code_pos);
                bool have_code_close = matches.fetch_pos (3, out start_after_pos, out end_after_pos);

                if (have_code_start && have_code && have_code_close) {
                    start_before_pos = buffer_text.char_count ((ssize_t) start_before_pos);
                    end_before_pos = buffer_text.char_count ((ssize_t) end_before_pos);
                    start_code_pos = buffer_text.char_count ((ssize_t) start_code_pos);
                    end_code_pos = buffer_text.char_count ((ssize_t) end_code_pos);
                    start_after_pos = buffer_text.char_count ((ssize_t) start_after_pos);
                    end_after_pos = buffer_text.char_count ((ssize_t) end_after_pos);

                    // Convert the character offsets to TextIter's
                    Gtk.TextIter start_before_iter, end_before_iter;
                    Gtk.TextIter start_code_iter,   end_code_iter;
                    Gtk.TextIter start_after_iter,  end_after_iter;
                    buffer.get_iter_at_offset (out start_before_iter, start_before_pos);
                    buffer.get_iter_at_offset (out end_before_iter, end_before_pos);
                    buffer.get_iter_at_offset (out start_code_iter, start_code_pos);
                    buffer.get_iter_at_offset (out end_code_iter, end_code_pos);
                    buffer.get_iter_at_offset (out start_after_iter, start_after_pos);
                    buffer.get_iter_at_offset (out end_after_iter, end_after_pos);

                    // Apply styling
                    remove_tags (start_before_iter, end_after_iter);

                    buffer.apply_tag (text_tag_code_span, start_code_iter, end_code_iter);
                    buffer.apply_tag (text_tag_around, start_before_iter, end_before_iter);
                    buffer.apply_tag (text_tag_around, start_after_iter, end_after_iter);

                    // Skip if our cursor is inside the code
                    if (cursor_location.in_range (start_before_iter, end_after_iter)) {
                        continue;
                    }

                    buffer.apply_tag (text_tag_hidden, start_before_iter, end_before_iter);
                    buffer.apply_tag (text_tag_hidden, start_after_iter, end_after_iter);
                }
            } while (matches.next ());
        }
    }

    void format_escape (
        string buffer_text,
        Gtk.TextIter cursor_location,
        out MatchInfo matches
    ) throws RegexError {
        // Check for escapes
        if (is_escape.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
            do {
                int start_text_pos, end_text_pos;
                bool have_text = matches.fetch_pos (0, out start_text_pos, out end_text_pos);

                if (have_text) {
                    start_text_pos = buffer_text.char_count ((ssize_t) start_text_pos);
                    end_text_pos = buffer_text.char_count ((ssize_t) end_text_pos);

                    // Convert the character offsets to TextIter's
                    Gtk.TextIter start_text_iter, end_text_iter;
                    buffer.get_iter_at_offset (out start_text_iter, start_text_pos);
                    buffer.get_iter_at_offset (out end_text_iter, end_text_pos);

                    var start_escaped_char_iter = start_text_iter.copy ();
                    start_escaped_char_iter.forward_char ();

                    // Skip if our cursor is inside the URL text
                    if (cursor_location.in_range (start_text_iter, end_text_iter)) {
                        continue;
                    }

                    // Apply styling
                    buffer.apply_tag (text_tag_escaped, start_escaped_char_iter, end_text_iter);
                    buffer.apply_tag (text_tag_hidden, start_text_iter, start_escaped_char_iter);
                }
            } while (matches.next ());
        }
    }

    void do_formatting_pass (
        Regex regex,
        Gtk.TextTag text_tag,
        string buffer_text,
        Gtk.TextIter cursor_location,
        out MatchInfo matches
    ) throws RegexError {
        if (regex.match_full (buffer_text, buffer_text.length, 0, 0, out matches)) {
            do {
                int start_before_pos, end_before_pos;
                int start_code_pos,   end_code_pos;
                int start_after_pos,  end_after_pos;
                bool have_code_start = matches.fetch_pos (1, out start_before_pos, out end_before_pos);
                bool have_code = matches.fetch_pos (2, out start_code_pos, out end_code_pos);
                bool have_code_close = matches.fetch_pos (3, out start_after_pos, out end_after_pos);

                if (have_code_start && have_code && have_code_close) {
                    start_before_pos = buffer_text.char_count ((ssize_t) start_before_pos);
                    end_before_pos = buffer_text.char_count ((ssize_t) end_before_pos);
                    start_code_pos = buffer_text.char_count ((ssize_t) start_code_pos);
                    end_code_pos = buffer_text.char_count ((ssize_t) end_code_pos);
                    start_after_pos = buffer_text.char_count ((ssize_t) start_after_pos);
                    end_after_pos = buffer_text.char_count ((ssize_t) end_after_pos);

                    // Convert the character offsets to TextIter's
                    Gtk.TextIter start_before_iter, end_before_iter;
                    Gtk.TextIter start_code_iter,   end_code_iter;
                    Gtk.TextIter start_after_iter,  end_after_iter;
                    buffer.get_iter_at_offset (out start_before_iter, start_before_pos);
                    buffer.get_iter_at_offset (out end_before_iter, end_before_pos);
                    buffer.get_iter_at_offset (out start_code_iter, start_code_pos);
                    buffer.get_iter_at_offset (out end_code_iter, end_code_pos);
                    buffer.get_iter_at_offset (out start_after_iter, start_after_pos);
                    buffer.get_iter_at_offset (out end_after_iter, end_after_pos);

                    // Apply styling
                    buffer.apply_tag (text_tag, start_code_iter, end_code_iter);
                    buffer.apply_tag (text_tag_around, start_before_iter, end_before_iter);
                    buffer.apply_tag (text_tag_around, start_after_iter, end_after_iter);

                    // Skip if our cursor is inside the code
                    if (cursor_location.in_range (start_before_iter, end_after_iter)) {
                        continue;
                    }

                    buffer.apply_tag (text_tag_hidden, start_before_iter, end_before_iter);
                    buffer.apply_tag (text_tag_hidden, start_after_iter, end_after_iter);
                }
            } while (matches.next ());
        }
    }
}
