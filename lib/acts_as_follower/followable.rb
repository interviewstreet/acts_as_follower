module ActsAsFollower #:nodoc:
  module Followable

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def acts_as_followable
        has_many :followings, :as => :followable, :dependent => :destroy, :class_name => 'Follow'
        include ActsAsFollower::Followable::InstanceMethods
        include ActsAsFollower::FollowerLib
      end
    end

    module InstanceMethods

      # Returns the number of followers a record has.
      def followers_count
        self.followings.status.unblocked.count
      end

      # Returns the followers by a given type
      def followers_by_type(follower_type, options={})
        follows = follower_type.constantize.
          joins(:follows).
          where('follows.status'          => true,
                'follows.blocked'         => false,
                'follows.followable_id'   => self.id,
                'follows.followable_type' => parent_class_name(self),
                'follows.follower_type'   => follower_type)
        if options.has_key?(:limit)
          follows = follows.limit(options[:limit])
        end
        if options.has_key?(:offset)
          follows = follows.offset(options[:offset])
        end
        if options.has_key?(:includes)
          follows = follows.includes(options[:includes])
        end
        follows
      end

      def followers_by_type_count(follower_type)
        self.followings.status.unblocked.for_follower_type(follower_type).count
      end

      # Allows magic names on followers_by_type
      # e.g. user_followers == followers_by_type('User')
      # Allows magic names on followers_by_type_count
      # e.g. count_user_followers == followers_by_type_count('User')
      def method_missing(m, *args)
        if m.to_s[/count_(.+)_followers/]
          followers_by_type_count($1.singularize.classify)
        elsif m.to_s[/(.+)_followers/]
          followers_by_type($1.singularize.classify)
        else
          super
        end
      end

      def respond_to?(m, include_private = false)
        super || m.to_s[/count_(.+)_followers/] || m.to_s[/(.+)_followers/]
      end

      def blocked_followers_count
        self.followings.blocked.count
      end

      # Returns the followings records scoped
      def followers_scoped
        self.followings.status.includes(:follower)
      end

      def followers(options={})
        self.followings.unblocked.status.includes(:follower).all(options).collect{|f| f.follower}
      end

      def blocks(options={})
        self.followings.blocked.includes(:follower).all(options).collect{|f| f.follower}
      end

      # Returns true if the current instance is followed by the passed record
      # Returns false if the current instance is blocked by the passed record or no follow is found
      def followed_by?(*args)
        if args.size == 2
          type, id = args[0], args[1]
          self.followings.unblocked.where(follower_type: type, follower_id: id).exists?
        elsif args.size == 1
          follower = args[0]
          self.followings.unblocked.for_follower(follower).exists?
        end
      end

      def block(follower)
        get_follow_for(follower) ? block_existing_follow(follower) : block_future_follow(follower)
      end

      def unblock(follower)
        get_follow_for(follower).try(:delete)
      end

      def get_follow_for(follower)
        self.followings.status.for_follower(follower).first
      end

      private

      def block_future_follow(follower)
        Follow.create(:followable => self, :follower => follower, :blocked => true)
      end

      def block_existing_follow(follower)
        get_follow_for(follower).block!
      end

    end

  end
end
