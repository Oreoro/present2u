module P2u
  # Declarative plan/apply. Compares a desired manifest with an existing deck
  # (matched by stable slide `p2u_id`, with a positional fallback for legacy
  # decks) and produces an ordered list of create/update/delete/reorder actions.
  class Planner
    class Action
      ATTRIBUTES = %i[action slide leaf_id changes slides].freeze
      attr_reader(*ATTRIBUTES)

      def initialize(action:, slide: nil, leaf_id: nil, changes: nil, slides: nil)
        @action = action.to_s
        @slide = slide
        @leaf_id = leaf_id
        @changes = changes
        @slides = slides
      end

      def to_h = ATTRIBUTES.index_with { |attribute| send(attribute) }.compact
    end

    class Result
      attr_reader :diagnostics, :actions, :book

      def initialize(diagnostics:, actions:, book: nil)
        @diagnostics = diagnostics
        @actions = actions
        @book = book
      end

      def valid? = diagnostics.none?(&:error?)
      def summary = actions.group_by(&:action).transform_values(&:size)

      def to_h
        {
          valid: valid?,
          deck: book && { id: book.id, title: book.title, slug: book.slug },
          summary: summary,
          actions: actions.map(&:to_h),
          diagnostics: diagnostics.map(&:to_h)
        }.compact
      end
    end

    def initialize(manifest, book:)
      @manifest = manifest.is_a?(Manifest) ? manifest : Manifest.new(manifest)
      @book = book
      @desired = Emitter.new(@manifest).slides.index_by { |slide| slide[:id] }
    end

    def plan
      diagnostics = Validator.new(@manifest).validate
      actions = diagnostics.any?(&:error?) ? [] : build_actions

      Result.new(diagnostics: diagnostics, actions: actions, book: @book)
    end

    def apply(user:)
      result = plan
      return result unless result.valid?

      @matches = matches

      @book.transaction do
        mapping = matches.dup
        result.actions.each do |action|
          case action.action
          when "create" then mapping[action.slide] = create_slide(action, user)
          when "update" then mapping[action.slide] = update_slide(action)
          when "delete" then delete_slide(action)
          end
        end

        reorder(mapping) if result.actions.any? { |action| action.action == "reorder" }
      end

      result
    end

    private
      def existing_leaves
        @existing_leaves ||= @book.leaves.active.with_leafables.positioned.to_a
      end

      def matches
        @matches ||= compute_matches
      end

      def compute_matches
        desired = @manifest.slides
        matched = {}

        existing_leaves.each do |leaf|
          next if leaf.p2u_id.blank?

          matched[leaf.p2u_id] = leaf if desired.any? { |slide| slide["id"] == leaf.p2u_id }
        end

        unmatched_desired = desired.reject { |slide| matched.key?(slide["id"]) }
        unmatched_existing = existing_leaves.reject { |leaf| matched.value?(leaf) }
        unmatched_desired.zip(unmatched_existing).each do |slide, leaf|
          matched[slide["id"]] = leaf if leaf
        end

        matched
      end

      def build_actions
        actions = []

        @manifest.slides.each do |slide|
          leaf = matches[slide["id"]]

          if leaf
            changes = changes_for(leaf, @desired.fetch(slide["id"]))
            actions << Action.new(action: "update", slide: slide["id"], leaf_id: leaf.id, changes: changes) if changes.any?
          else
            actions << Action.new(action: "create", slide: slide["id"])
          end
        end

        existing_leaves.each do |leaf|
          next if matches.value?(leaf)

          actions << Action.new(action: "delete", slide: leaf.p2u_id.presence || leaf.title, leaf_id: leaf.id)
        end

        if reorder_needed?
          actions << Action.new(action: "reorder", slides: @manifest.slides.map { |slide| slide["id"] })
        end

        actions
      end

      def reorder_needed?
        return true if @manifest.slides.any? { |slide| matches[slide["id"]].nil? }

        current = existing_leaves.select { |leaf| matches.value?(leaf) }.map(&:id)
        expected = @manifest.slides.filter_map { |slide| matches[slide["id"]]&.id }
        current != expected
      end

      def changes_for(leaf, desired)
        changes = {}
        compare(changes, "title", leaf.title, desired[:title])
        compare(changes, "notes", leaf.notes, desired[:notes])
        compare(changes, "sketch", leaf.sketch, desired[:sketch])
        compare(changes, "layout", current_layout(leaf), desired[:layout])
        compare_leafable(changes, leaf, desired)
        changes
      end

      def current_layout(leaf)
        leaf.layout.presence || Layouts.resolve(leaf.leafable_name)
      end

      def compare_leafable(changes, leaf, desired)
        case leaf.leafable_name.to_s
        when "page"
          compare(changes, "body", leaf.page.body.content.to_s, desired[:body])
        when "section"
          compare(changes, "body", leaf.section.body, desired[:body])
          compare(changes, "theme", leaf.section.theme, desired[:theme])
        when "picture"
          compare(changes, "caption", leaf.picture.caption, desired[:caption])
        when "typst"
          compare(changes, "source", leaf.typst.source, desired[:source])
        end
      end

      def compare(changes, field, current, desired)
        return if current.to_s.strip == desired.to_s.strip

        changes[field] = [ current, desired ]
      end

      def create_slide(action, user)
        DeckBuilder.new(user).add_slide(@book, @desired.fetch(action.slide))
      end

      def update_slide(action)
        leaf = @book.leaves.active.find(action.leaf_id)
        desired = @desired.fetch(action.slide)

        leaf.edit(leafable_params: leafable_params_for(leaf, desired), leaf_params: leaf_params_for(desired))
        leaf.reload
      end

      def delete_slide(action)
        @book.leaves.active.find(action.leaf_id).trashed!
      end

      def leaf_params_for(desired)
        {
          title: desired[:title],
          notes: desired[:notes],
          sketch: desired[:sketch],
          layout: desired[:layout],
          p2u_id: desired[:id]
        }
      end

      def leafable_params_for(leaf, desired)
        case leaf.leafable_name.to_s
        when "page" then { body: desired[:body].to_s }
        when "section" then { body: desired[:body], theme: desired[:theme] }
        when "typst" then { source: desired[:source].to_s }
        when "picture" then { caption: desired[:caption] }
        else {}
        end
      end

      # Move every slide to the end in manifest order, which leaves the deck in
      # the desired order.
      def reorder(mapping)
        count = @book.leaves.active.count

        @manifest.slides.each do |slide|
          leaf = mapping[slide["id"]] || @book.leaves.active.find_by(p2u_id: slide["id"])
          leaf&.move_to_position(count)
        end
      end
  end
end
