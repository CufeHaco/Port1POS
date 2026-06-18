# lib/gui/tk_main.rb - Tk/ttk GUI for Port1POS (Register side)
# Using ttk (themed Tk widgets) for a modern, native-looking interface
# Base design & functionality modeled after LiquorPOS (legacy Windows liquor store POS)
#
# Following Cufe style where applicable.
#
# This is the main Port1POS application GUI ("the app guide"):
#   - Full menu bar (File, Transaction, Inventory, Reports, Tools)
#   - Child windows for common liquor store functions
#   - Transaction screen with scan, list, tender, age verification
#
# Key LiquorPOS-inspired features implemented:
#   - Transaction loop (scan → add → age prompt on tender)
#   - Inventory receiving with case/pack/bottle breakdown
#   - Item lookup / price check
#   - Basic reporting stub
#   - Settings
#
# Requires: ruby setup/install_tk.rb (for ttk + Tcl/Tk 8.6)
# Run: ruby lib/gui/tk_main.rb

begin
  require 'tk'
rescue LoadError => e
  abort <<~MSG
    [Port1POS GUI] Tk could not be loaded.

    Please run the integrated installer first:
      ruby setup/install_tk.rb

    Then re-run this GUI.
  MSG
end

module Port1POS
  module GUI
    class TkMain
      def initialize
        @transaction = []
        @total = 0.0
        @age_verified = false
        @ipc = nil
        build_ui
      end

      def build_ui
        @root = TkRoot.new do
          title "Port1POS — Liquor Store Register (LiquorPOS Compatible)"
          geometry "860x640"
          resizable true, true
        end

        build_menu
        build_main_screen
        @root.bind 'Destroy', proc { cleanup }
      end

      # ==================== MENU ==================== 
      def build_menu
        menubar = TkMenu.new(@root)
        @root.menu menubar

        # File
        file = TkMenu.new(menubar)
        menubar.add :cascade, menu: file, label: "File"
        file.add :command, label: "New Transaction", command: proc { new_transaction }
        file.add :command, label: "Suspend Transaction", command: proc { Tk.messageBox message: "Suspend/Recall coming soon" }
        file.add :separator
        file.add :command, label: "Exit", command: proc { exit }

        # Transaction
        tx = TkMenu.new(menubar)
        menubar.add :cascade, menu: tx, label: "Transaction"
        tx.add :command, label: "Void Last Item", command: proc { void_last_item }
        tx.add :command, label: "Void Entire Transaction", command: proc { void_transaction }
        tx.add :separator
        tx.add :command, label: "Price Check", command: proc { show_item_lookup }

        # Inventory (LiquorPOS style)
        inv = TkMenu.new(menubar)
        menubar.add :cascade, menu: inv, label: "Inventory"
        inv.add :command, label: "Item Lookup / Price Check", command: proc { show_item_lookup }
        inv.add :command, label: "Receive Inventory (Case/Pack/Bottle)", command: proc { show_inventory_receive }
        inv.add :command, label: "Quick Stock Count", command: proc { Tk.messageBox message: "Stock count window coming in next iteration" }

        # Reports
        rep = TkMenu.new(menubar)
        menubar.add :cascade, menu: rep, label: "Reports"
        rep.add :command, label: "Daily Sales Summary", command: proc { show_reports }
        rep.add :command, label: "Compliance / Age Log", command: proc { show_compliance_log }
        rep.add :command, label: "Keg & Inventory Movement", command: proc { Tk.messageBox message: "Keg log window coming soon" }

        # Tools
        tools = TkMenu.new(menubar)
        menubar.add :cascade, menu: tools, label: "Tools"
        tools.add :command, label: "Settings", command: proc { show_settings }
        tools.add :command, label: "Hardware Test (Scanner / Printer)", command: proc { test_hardware }
        tools.add :separator
        tools.add :command, label: "About Port1POS", command: proc { show_about }

        # Help
        help = TkMenu.new(menubar)
        menubar.add :cascade, menu: help, label: "Help"
        help.add :command, label: "App Guide / User Manual", command: proc { show_app_guide }
      end

      # ==================== MAIN TRANSACTION SCREEN ====================
      def build_main_screen
        # Top scan bar
        top = Tk::Tile::Frame.new(@root) { pack fill: 'x', padx: 8, pady: 6 }
        Tk::Tile::Label.new(top) { text "Scan / PLU:"; pack side: 'left', padx: 4 }
        @scan_entry = Tk::Tile::Entry.new(top) { width 30; pack side: 'left', padx: 4; bind 'Return', proc { add_item_from_scan } }
        Tk::Tile::Button.new(top) { text "Add"; command proc { add_item_from_scan }; pack side: 'left', padx: 4 }

        # Main area
        middle = Tk::Tile::Frame.new(@root) { pack fill: 'both', expand: true, padx: 8, pady: 4 }

        # Transaction list
        list_frame = Tk::Tile::Frame.new(middle) { pack side: 'left', fill: 'both', expand: true }
        @listbox = TkListbox.new(list_frame) { height 18; width 90; pack side: 'left', fill: 'both', expand: true }
        TkScrollbar.new(list_frame) { command proc { |*a| @listbox.yview(*a) }; pack side: 'right', fill: 'y' }

        # Right panel
        right = Tk::Tile::Frame.new(middle) { pack side: 'right', fill: 'y', padx: 10 }

        Tk::Tile::Label.new(right) { text "TOTAL"; pack pady: 2 }
        @total_label = Tk::Tile::Label.new(right) { text "$0.00"; font TkFont.new(size: 22, weight: 'bold'); pack pady: 2 }

        Tk::Tile::Button.new(right) { text "Tender CASH"; width 18; command proc { tender(:cash) }; pack pady: 3, fill: 'x' }
        Tk::Tile::Button.new(right) { text "Tender CREDIT"; width 18; command proc { tender(:credit) }; pack pady: 3, fill: 'x' }
        Tk::Tile::Button.new(right) { text "Tender CHECK"; width 18; command proc { tender(:check) }; pack pady: 3, fill: 'x' }

        Tk::Tile::Separator.new(right) { pack fill: 'x', pady: 8 }

        Tk::Tile::Button.new(right) { text "VERIFY AGE"; width 18; command proc { prompt_age_verification }; pack pady: 3, fill: 'x' }

        # Status
        @status = Tk::Tile::Label.new(@root) { text "Ready | Menu → Inventory/Reports for full LiquorPOS-style functions"; anchor 'w'; pack fill: 'x', side: 'bottom', padx: 8, pady: 4 }

        update_display
      end

      # ==================== CHILD WINDOWS ====================

      def show_item_lookup
        win = TkToplevel.new(@root) { title "Item Lookup / Price Check — Port1POS" }
        Tk::Tile::Label.new(win) { text "Enter SKU / PLU or scan item"; pack pady: 8 }

        entry = Tk::Tile::Entry.new(win) { width 25; pack pady: 4 }
        result_label = Tk::Tile::Label.new(win) { text " "; pack pady: 10 }

        Tk::Tile::Button.new(win) do
          text "Lookup"
          command proc {
            code = entry.get.strip
            item = build_item_from_code(code)
            if item
              result_label.text = "#{item[:desc]}  —  $#{item[:price]}  (#{item[:qty]} unit)"
            else
              result_label.text = "Item not found"
            end
          }
          pack pady: 4
        end

        Tk::Tile::Button.new(win) { text "Close"; command proc { win.destroy }; pack pady: 6 }
      end

      def show_inventory_receive
        win = TkToplevel.new(@root) { title "Receive Inventory — Port1POS (LiquorPOS style)" }

        Tk::Tile::Label.new(win) { text "SKU / Item"; pack pady: 4 }
        sku_entry = Tk::Tile::Entry.new(win) { width 20; pack }

        Tk::Tile::Label.new(win) { text "Cases Received"; pack pady: 4 }
        cases = Tk::Tile::Entry.new(win) { width 8; pack }

        Tk::Tile::Label.new(win) { text "Packs per Case"; pack pady: 4 }
        packs = Tk::Tile::Entry.new(win) { width 8; pack }

        Tk::Tile::Label.new(win) { text "Bottles per Pack"; pack pady: 4 }
        bottles = Tk::Tile::Entry.new(win) { width 8; pack }

        Tk::Tile::Button.new(win) do
          text "Record Receiving"
          command proc {
            msg = "Received: #{cases.get} cases × #{packs.get} packs × #{bottles.get} bottles\n(Saved to DBF + audit log in full version)"
            Tk.messageBox message: msg, title: "Inventory Received"
            win.destroy
          }
          pack pady: 10
        end

        Tk::Tile::Button.new(win) { text "Cancel"; command proc { win.destroy }; pack }
      end

      def show_reports
        win = TkToplevel.new(@root) { title "Daily Sales & Reports — Port1POS" }
        Tk::Tile::Label.new(win) { text "Daily Sales Summary (Demo)"; font TkFont.new(size: 14, weight: 'bold'); pack pady: 8 }

        text = TkText.new(win) do
          width 60; height 12; pack padx: 10, pady: 6
          insert 'end', "Date: #{Time.now.strftime('%Y-%m-%d')}\n"
          insert 'end', "Total Sales: $#{rand(1800..4200)}.#{rand(10..99)}\n"
          insert 'end', "Transactions: #{rand(45..120)}\n"
          insert 'end', "Alcohol Items: #{rand(30..80)}\n"
          insert 'end', "Age Checks Performed: #{rand(12..35)}\n"
          insert 'end', "\n(Full reports will pull from DBF + Kestówv analytics)"
        end

        Tk::Tile::Button.new(win) { text "Close"; command proc { win.destroy }; pack pady: 6 }
      end

      def show_compliance_log
        win = TkToplevel.new(@root) { title "Compliance / Age Verification Log" }
        Tk::Tile::Label.new(win) { text "Recent Age Verifications (Demo)"; pack pady: 6 }

        log_text = TkText.new(win) { width 55; height 10; pack padx: 8 }
        log_text.insert 'end', "2026-06-18 14:22 - SKU 12345 - Age verified (30+)\n"
        log_text.insert 'end', "2026-06-18 14:15 - SKU 67890 - ID checked (under 30)\n"
        log_text.insert 'end', "2026-06-18 13:58 - SKU 11111 - Age verified (30+)\n"

        Tk::Tile::Button.new(win) { text "Close"; command proc { win.destroy }; pack pady: 6 }
      end

      def show_settings
        win = TkToplevel.new(@root) { title "Port1POS Settings" }

        Tk::Tile::Label.new(win) { text "Store Settings (Demo)"; pack pady: 8 }

        Tk::Tile::CheckButton.new(win) { text "Require Age Verification on all alcohol sales"; pack pady: 2 }
        Tk::Tile::CheckButton.new(win) { text "Enable Georgia Compliance Logging"; pack pady: 2 }
        Tk::Tile::CheckButton.new(win) { text "Auto-print receipts after tender"; pack pady: 2 }

        Tk::Tile::Button.new(win) do
          text "Save Settings"
          command proc {
            Tk.messageBox message: "Settings saved (will persist in full version)"
            win.destroy
          }
          pack pady: 10
        end
      end

      def test_hardware
        Tk.messageBox message: "Hardware Test\n\nScanner: OK (via MicroIPC)\nPrinter: Connected to print_server\n\n(Full test will use MicroIPC + PrintServer)", title: "Hardware Test"
      end

      def show_about
        Tk.messageBox message: "Port1POS v0.1\nModern JRuby replacement for LiquorPOS\n\nTk/ttk GUI + MicroIPC + Kestówv stack\n\nhttps://github.com/CufeHaco/Port1POS", title: "About Port1POS"
      end

      def show_app_guide
        win = TkToplevel.new(@root) { title "Port1POS App Guide" }
        text = TkText.new(win) { width 70; height 18; pack padx: 10, pady: 8 }
        text.insert 'end', <<~GUIDE
          Port1POS — Quick User Guide (LiquorPOS style)

          1. Main Screen
             • Scan or type PLU → Add Item
             • See live transaction list + total
             • Tender with CASH / CREDIT / CHECK
             • Always VERIFY AGE on alcohol items (Georgia rule)

          2. Menu → Inventory
             • Item Lookup / Price Check
             • Receive Inventory (enter Cases × Packs × Bottles)

          3. Menu → Reports
             • Daily Sales Summary
             • Compliance / Age Log

          4. Menu → Tools
             • Settings
             • Hardware Test (Scanner + Printer via MicroIPC)

          Future:
          • Full DBF compatibility (LiquorPOS files)
          • Real backend via MicroIPC + Print Server
          • Multi-register support
        GUIDE
        Tk::Tile::Button.new(win) { text "Close"; command proc { win.destroy }; pack pady: 4 }
      end

      # ==================== CORE LOGIC ====================

      def add_item_from_scan
        code = @scan_entry.get.strip
        return if code.empty?
        item = build_item_from_code(code)
        if item
          @transaction << item
          @total += item[:total]
          update_display
          @scan_entry.delete 0, 'end'
        else
          Tk.messageBox message: "Item #{code} not found", icon: 'error'
        end
      end

      def build_item_from_code(code)
        demo = {
          '12345' => { sku: '12345', desc: 'Bourbon 750ml', qty: 1, price: 24.99 },
          '67890' => { sku: '67890', desc: 'Vodka 1L', qty: 1, price: 18.50 },
          '11111' => { sku: '11111', desc: 'Craft Beer 6pk', qty: 1, price: 12.99 }
        }
        base = demo[code] || { sku: code, desc: "Item #{code}", qty: 1, price: 9.99 }
        base.merge(total: (base[:qty] * base[:price]).round(2))
      end

      def tender(type)
        return if @transaction.empty?
        unless @age_verified
          return unless prompt_age_verification
        end
        Tk.messageBox message: "Tendered $#{@total.round(2)} via #{type}\n\n(Will send to MicroIPC + PrintServer in next version)"
        new_transaction
      end

      def void_last_item
        return if @transaction.empty?
        item = @transaction.pop
        @total -= item[:total]
        update_display
      end

      def void_transaction
        @transaction.clear
        @total = 0.0
        @age_verified = false
        update_display
      end

      def prompt_age_verification
        dlg = TkToplevel.new(@root) { title "Age Verification" }
        Tk::Tile::Label.new(dlg) { text "Does customer appear under 30?"; pack pady: 10 }
        result = nil
        Tk::Tile::Button.new(dlg) { text "YES - Check ID"; command proc { result = true; dlg.destroy }; pack side: 'left', padx: 5 }
        Tk::Tile::Button.new(dlg) { text "NO - 30+"; command proc { @age_verified = true; result = true; dlg.destroy }; pack side: 'left', padx: 5 }
        dlg.grab; dlg.wait_window
        result
      end

      def new_transaction
        @transaction.clear
        @total = 0.0
        @age_verified = false
        update_display
      end

      def update_display
        @listbox.delete 0, 'end'
        @transaction.each do |item|
          line = sprintf("%-10s %-24s %2dx $%6.2f = $%6.2f", item[:sku], item[:desc], item[:qty], item[:price], item[:total])
          @listbox.insert 'end', line
        end
        @total_label.text = "$#{@total.round(2)}"
      end

      def cleanup
        @ipc&.close if @ipc
      end

      def run
        Tk.mainloop
      end
    end
  end
end

if __FILE__ == $0
  puts "Launching Port1POS ttk GUI with full menu + child windows..."
  Port1POS::GUI::TkMain.new.run
end
