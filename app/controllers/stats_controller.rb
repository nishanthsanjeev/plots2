class StatsController < ApplicationController
  def subscriptions
    @tags = {}
    TagSelection.where(following: true).each do |tag|
      @tags[tag.tagname] = @tags[tag.tagname] || 0
      @tags[tag.tagname] += 1
    end
    @tags = @tags.group_by { |_k, v| v / 10 }
  end

  def range
    flash.now[:notice] = "Data is cached and recalculated daily"
    if params[:options].present?
      params[:start] = Time.now - to_keyword(params[:options])
      params[:end] = Time.now
    end
    @start = start
    @end = fin
    Rails.cache.fetch("range-#{@start.to_i}-#{@end.to_i}", expires_in: 1.day) do
      @notes = Node.published.select(%i(created type))
        .where(type: 'note', created: @start.to_i..@end.to_i)
        .size
      @wikis = Revision.published.select(:timestamp)
        .where(timestamp: @start.to_i..@end.to_i)
        .size - @notes # because notes each have one revision
      @people = User.where(created_at: @start..@end).where(status: 1)
        .size
      @comments = Comment.select(:status, :timestamp)
        .where(status: 1, timestamp: @start.to_i..@end.to_i)
        .size
      @contributors = User.contributor_count_for(@start, @end)
      @popular_tags = Tag.nodes_frequency(@start, @end)

      total_questions = Node.published.questions
        .where(created: @start.to_i..@end.to_i)
      @answers = total_questions.joins(:comments).size.count
      @questions = total_questions.size.count
    end
  end

  def index
    range
    if @start > @end
      flash.now[:warning] = "Start date must come before end date"
    end
    @title = 'Stats'

    flash.now[:notice] = "Data is cached and recalculated daily"
    Rails.cache.fetch("stats-index-#{@start.to_i}-#{@end.to_i}", expires_in: 1.day) do
      @weekly_notes = Node.past_week.select(:type).where(type: 'note').size
      @weekly_wikis = Revision.past_week.size
      @weekly_questions = Node.questions.past_week.size
      @weekly_answers = Answer.past_week.size
      @weekly_members = User.past_week.where(status: 1).size
      @monthly_notes = Node.past_month.select(:type).where(type: 'note').size
      @monthly_wikis = Revision.past_month.size
      @monthly_members = User.past_month.where(status: 1).size
      @monthly_questions = Node.questions.past_month.size
      @monthly_answers = Answer.past_month.size

      @notes_per_week_period = Node.frequency('note', @start, @end).round(2)
      @edits_per_week_period = Revision.frequency(@start, @end).round(2)

      @graph_notes = Node.contribution_graph_making('note', @start, @end)
      @graph_wikis = Node.contribution_graph_making('page', @start, @end)
      @graph_comments = Comment.contribution_graph_making(@start, @end)

      users = []
      nids = []
      Node.published.where(type: 'note').each do |note|
        unless note.uid == 674 || note.uid == 671
          users << note.uid
          nids << note.nid
        end
      end

      @all_notes = nids.uniq.length
      @all_contributors = users.uniq.length
    end
    Rails.cache.fetch("total-contributors-all-time", expires_in: 1.weeks) do
      @all_time_contributors = User.count_all_time_contributor
    end
  end

  def notes
    export_as_json('note')
  end

  def wikis
    export_as_json('page')
  end

  def users
    data = User.where(created_at: start..fin)
          .where(status: 1)
         .select(:username, :role, :bio, :photo_file_name, :id, :created_at)
    format(data, 'users')
  end

  def questions
    data = Node.published.questions.where(created: start.to_i..fin.to_i).all
    format(data, 'questions')
  end

  def answers
    data = Answer.where(created_at: start..fin).all
    format(data, 'answers')
  end

  def comments
    data = Comment.where(status: 1, timestamp: start.to_i...fin.to_i).all
    format(data, 'comment')
  end

  def tags
    data = Tag.select(:tid, :name, :parent, :count).all
    format(data, 'tag')
  end

  def node_tags
    data = NodeTag.select(:tid, :nid, :uid).where(date: start.to_i...fin.to_i).all
    format(data, 'node_tag')
  end

  def export_as_json(type)
    data = Node.published
      .where(type: type, created: start.to_i..fin.to_i)
      .all
    format(data, type)
  end

  private

  def start
    params[:start] ? Time.parse(params[:start].to_s) : Time.now - 3.months
  end

  def fin
    params[:end] ? Time.parse(params[:end].to_s) : Time.now
  end

  def to_keyword(param)
    str = param.split.second
    1.send(str.downcase)
  end

  def format(data, name)
    respond_to do |format|
      format.csv { send_data data.to_csv, type: 'text/csv' }
      format.json { send_data data.to_json, type: 'application/json; header=present', disposition: "attachment; filename=#{name}.json" }
    end
  end
end
