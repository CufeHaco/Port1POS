# lib/gui/tk_main.rb - Tk/ttk GUI for Port1POS (Register side)
# Using ttk (themed Tk widgets) for a modern, native-looking interface
# Following Cufe style where applicable:
#   - Modular, self-documenting
#   - Build state (current transaction as array) → Match action → Verify (age/compliance gates) → Execute
#   - Threaded Tk note: Tk must stay in main thread. Use queues/Thread for IPC and heavy work.
#
# This is the main Port1POS application GUI (the "app guide"):
#   - Scan/PLU entry (ttk)
#   - Transaction list + running total
#   - Quick tender buttons (ttk)
#   - Age verification dialog (Georgia liquor compliance — ttk themed)
#   - Status bar + future IPC wiring point
#
# Requires Tcl/Tk 8.6+ (provided by setup/install_tk.rb)
# Run standalone: ruby lib/gui/tk_main.rb
# Later: integrate with boot.rb + MicroIPC for real backend

begin
  require 'tk'
rescue LoadError => e
  abort <<~MSG
    [Port1POS GUI] Tk could not be loaded: #{e.message}

    The Tk GUI requires a working Ruby Tk (tk gem + Tcl/Tk 8.6) installation.

    Please run the integrated Port1POS Tk installer first:

      ruby setup/install_tk.rb

    (This contains Cufe's rubytk_patchV2 logic integrated directly into Port1POS
     for a self-contained cross-platform experience.)

    After it completes successfully, re-run this GUI.
  MSG
end

# Use ttk (themed) widgets where available for modern look
module Port1POS
  module GUI
    class TkMain
      def initialize(options = {})
        @options = options
        @transaction = []          # array of {sku:, desc:, qty:, price:, total:}
        @total = 0.0
        @ipc = nil                 # MicroIPC instance when wired
        @age_verified = false

        build_ui
      end

      def build_ui
        @root = TkRoot.new do
          title "Port1POS — Liquor Store Register"
          geometry "820x620"
          resizable true, true
        end

        # Use ttk styles where possible
        style = Tk::Tile::Style.new

        # Top frame: Scan input (ttk)
        top = Tk::Tile::Frame.new(@root) { pack fill: 'x', padx: 10, pady: 8 }
        Tk::Tile::Label.new(top) { text "Scan / PLU:"; pack side: 'left', padx: 5 }
        @scan_entry = Tk::Tile::Entry.new(top) do
          width 32
          pack side: 'left', padx: 5
          bind 'Return', proc { add_item_from_scan }
        end
        Tk::Tile::Button.new(top) { text "Add Item"; command proc { add_item_from_scan }; pack side: 'left', padx: 5 }

        # Main content area
        middle = Tk::Tile::Frame.new(@root) { pack fill: 'both', expand: true, padx: 10, pady: 5 }

        # Transaction list (classic Listbox for simplicity; can upgrade to Ttk::Treeview later)
        list_frame = Tk::Tile::Frame.new(middle) { pack side: 'left', fill: 'both', expand: true }
        @listbox = TkListbox.new(list_frame) do
          height 16
          width 85
          pack side: 'left', fill: 'both', expand: true
        end
        TkScrollbar.new(list_frame) do
          command proc { |*args| @listbox.yview(*args) }
          pack side: 'right', fill: 'y'
        end

        # Right sidebar: Totals + actions (ttk)
        right = Tk::Tile::Frame.new(middle) { pack side: 'right', fill: 'y', padx: 12 }

        Tk::Tile::Label.new(right) { text "Current Total"; pack pady: 6 }
        @total_label = Tk::Tile::Label.new(right) do
          text "$0.00"
          font TkFont.new(size: 20, weight: 'bold')
          pack pady: 4
        end

        # Tender buttons (ttk styled)
        Tk::Tile::Button.new(right) { text "Tender CASH"; width 20; command proc { tender(:cash) }; pack pady: 4, fill: 'x' }
        Tk::Tile::Button.new(right) { text "Tender CREDIT"; width 20; command proc { tender(:credit) }; pack pady: 4, fill: 'x' }
        Tk::Tile::Button.new(right) { text "Tender CHECK"; width 20; command proc { tender(:check) }; pack pady: 4, fill: 'x' }

        Tk::Tile::Separator.new(right) { pack fill: 'x', pady: 10 }

        # Compliance critical: Age verification (ttk)
        age_btn = Tk::Tile::Button.new(right) do
          text "VERIFY AGE"
          width 20
          command proc { prompt_age_verification }
          pack pady: 4, fill: 'x'
        end
        # Give it a distinct style if possible
        begin
          age_btn['style'] = 'Accent.TButton' rescue nil
        end

        # Bottom status bar
        @status = Tk::Tile::Label.new(@root) do
          text "Ready — IPC: not connected (demo mode)  |  Use setup/install_tk.rb if Tk is missing"
          anchor 'w'
          pack fill: 'x', side: 'bottom', padx: 10, pady: 6
        end

        # Minimal menu
        menu = TkMenu.new(@root)
        @root.menu menu
        file_menu = TkMenu.new(menu)
        menu.add :cascade, menu: file_menu, label: 'File'
        file_menu.add :command, label: 'New Transaction', command: proc { new_transaction }
        file_menu.add :separator
        file_menu.add :command, label: 'Exit', command: proc { exit }

        update_display
        @root.bind 'Destroy', proc { cleanup }
      end

      # === Core logic (Build-Match-Verify-Execute style) ===

      def add_item_from_scan
        code = @scan_entry.get.strip
        return if code.empty?

        item = build_item_from_code(code)

        if item
          @transaction << item
          @total += item[:total]
          update_display
          @scan_entry.delete 0, 'end'
          @status.text = "Added #{item[:desc]}"
        else
          Tk.messageBox type: 'ok', icon: 'error', title: 'Item Not Found',
                        message: "No item found for code: #{code}"
        end
      end

      def build_item_from_code(code)
        # Placeholder — later replace with real DBF / MicroIPC lookup
        demo_items = {
          '12345' => { sku: '12345', desc: 'Bourbon 750ml', qty: 1, price: 24.99 },
          '67890' => { sku: '67890', desc: 'Vodka 1L',      qty: 1, price: 18.50 },
          '11111' => { sku: '11111', desc: 'Craft Beer 6pk', qty: 1, price: 12.99 }
        }
        base = demo_items[code] || { sku: code, desc: "Item #{code}", qty: 1, price: 9.99 }
        total = (base[:qty] * base[:price]).round(2)
        base.merge(total: total)
      end

      def tender(type)
        return if @transaction.empty?

        unless @age_verified
          result = prompt_age_verification
          return unless result
        end

        Tk.messageBox type: 'ok', icon: 'info', title: "Tender #{type.to_s.upcase}",
                      message: "Tendered $#{@total.round(2)} via #{type}\n\nTransaction complete.\n(IPC print + backend would fire here)"

        new_transaction
      end

      def prompt_age_verification
        dlg = TkToplevel.new(@root) { title "Age Verification — Port1POS" }

        Tk::Tile::Label.new(dlg) { text "Does the customer appear to be under 30 years old?"; pack pady: 12, padx: 20 }

        btn_frame = Tk::Tile::Frame.new(dlg) { pack pady: 10 }

        result = nil

        Tk::Tile::Button.new(btn_frame) do
          text "YES — Check ID"
          command proc {
            result = true
            dlg.destroy
            Tk.messageBox type: 'ok', icon: 'warning', title: 'ID Check Required',
                          message: "Please verify ID / scan DOB.\n\n(Full DOB entry + compliance logging coming in next iteration)"
          }
          pack side: 'left', padx: 6
        end

        Tk::Tile::Button.new(btn_frame) do
          text "NO — Looks 30+"
          command proc {
            result = true
            @age_verified = true
            dlg.destroy
            @status.text = "Age verified (appears 30+)"
          }
          pack side: 'left', padx: 6
        end

        Tk::Tile::Button.new(btn_frame) do
          text "Cancel"
          command proc { dlg.destroy }
          pack side: 'left', padx: 6
        end

        dlg.grab
        dlg.wait_window
        result
      end

      def new_transaction
        @transaction.clear
        @total = 0.0
        @age_verified = false
        update_display
        @status.text = "New transaction started"
      end

      def update_display
        @listbox.delete 0, 'end'
        @transaction.each do |item|
          line = sprintf("%-10s  %-25s  %2dx  $%6.2f  = $%6.2f",
                         item[:sku], item[:desc], item[:qty], item[:price], item[:total])
          @listbox.insert 'end', line
        end
        @total_label.text = "$#{@total.round(2)}"
      end

      def cleanup
        @ipc&.close if @ipc
        puts "[TkMain] GUI closed cleanly"
      end

      def run
        Tk.mainloop
      end
    end
  end
end

# Standalone launcher
if __FILE__ == $0
  puts "Starting Port1POS (ttk GUI)..."
  puts "If Tk is missing, run: ruby setup/install_tk.rb"
  gui = Port1POS::GUI::TkMain.new
  gui.run
end
