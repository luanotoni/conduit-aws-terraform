from rest_framework import serializers

from .models import Profile


class ProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username')
    bio = serializers.CharField(allow_blank=True, required=False)
    # Writable so PUT /api/user can actually change it (a SerializerMethodField
    # is read-only and silently dropped the value). Empty means "no image".
    image = serializers.URLField(
        allow_blank=True, allow_null=True, required=False, max_length=200
    )
    following = serializers.SerializerMethodField()

    class Meta:
        model = Profile
        fields = ('username', 'bio', 'image', 'following',)
        read_only_fields = ('username',)

    def validate_image(self, value):
        return value or ''

    def to_representation(self, instance):
        data = super().to_representation(instance)
        # The RealWorld spec uses null for "no image"; the frontend renders its
        # own fallback avatar instead of depending on a third-party URL.
        data['image'] = data['image'] or None
        return data

    def get_following(self, instance):
        request = self.context.get('request', None)

        if request is None:
            return False

        if not request.user.is_authenticated:
            return False

        follower = request.user.profile
        followee = instance

        return follower.is_following(followee)
