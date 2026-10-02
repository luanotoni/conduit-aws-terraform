from django.db import migrations


def create_missing_profiles(apps, schema_editor):
    User = apps.get_model("authentication", "User")
    Profile = apps.get_model("profiles", "Profile")

    existing_user_ids = Profile.objects.values_list("user_id", flat=True)
    profiles = [
        Profile(user_id=user_id)
        for user_id in User.objects.exclude(pk__in=existing_user_ids).values_list("pk", flat=True)
    ]
    Profile.objects.bulk_create(profiles)


class Migration(migrations.Migration):
    dependencies = [
        ("profiles", "0004_alter_profile_id"),
    ]

    operations = [
        migrations.RunPython(create_missing_profiles, migrations.RunPython.noop),
    ]
