class BooksController < ApplicationController
  allow_unauthenticated_access only: %i[ index show ]

  before_action :ensure_index_is_not_empty, only: :index
  before_action :set_book, only: %i[ show edit update destroy duplicate ]
  before_action :set_users, only: %i[ new edit ]
  before_action :ensure_editable, only: %i[ edit update destroy duplicate ]

  def index
    @books = Book.accessable_or_published.ordered
    @query = params[:q].to_s.strip

    if @query.present?
      like = "%#{@query}%"
      @books = @books.where(
        "books.title LIKE :q OR books.subtitle LIKE :q OR books.author LIKE :q",
        q: like
      )
    end
  end

  def new
    @book = Book.new
  end

  def create
    book = Book.create! book_params
    update_accesses(book)

    redirect_to book_slug_url(book)
  end

  def show
    @leaves = @book.leaves.active.with_leafables.positioned

    respond_to do |format|
      format.html
      format.md
    end
  end

  def edit
  end

  def update
    @book.update(book_params)
    update_accesses(@book)
    remove_cover if params[:remove_cover] == "true"

    redirect_to book_slug_url(@book)
  end

  def duplicate
    copy = @book.dup
    copy.title = "#{@book.title} (copy)"
    copy.published = false
    copy.everyone_access = false
    copy.save!
    copy.update_access(readers: [], editors: [ Current.user.id ])

    @book.leaves.positioned.each do |leaf|
      new_leaf = leaf.dup
      new_leaf.book = copy
      new_leaf.leafable = duplicate_leafable(leaf)
      new_leaf.save!
    end

    redirect_to book_slug_url(copy)
  end

  def destroy
    @book.destroy

    redirect_to root_url
  end

  private
    def set_book
      @book = Book.accessable_or_published.find params[:id]
    end

    def set_users
      @users = User.active.ordered
    end

    def ensure_editable
      head :forbidden unless @book.editable?
    end

    def ensure_index_is_not_empty
      if !signed_in? && Book.published.none?
        require_authentication
      end
    end

    def book_params
      params.require(:book).permit(:title, :subtitle, :author, :cover, :remove_cover, :everyone_access, :theme)
    end

    def update_accesses(book)
      editors = [ Current.user.id, *params[:editor_ids]&.map(&:to_i) ]
      readers = [ Current.user.id, *params[:reader_ids]&.map(&:to_i) ]

      book.update_access(editors: editors, readers: readers)
    end

    def remove_cover
      @book.cover.purge
    end

    def duplicate_leafable(leaf)
      case leaf.leafable_name.to_s
      when "section"
        Section.new(body: leaf.section.body)
      when "picture"
        picture = Picture.new(caption: leaf.picture.caption)
        picture.image.attach(leaf.picture.image.blob) if leaf.picture.image.attached?
        picture
      when "typst"
        Typst.new(source: leaf.typst.source)
      else
        page = Page.new
        page.body = leaf.page.body.content.to_s
        page
      end
    end
end
