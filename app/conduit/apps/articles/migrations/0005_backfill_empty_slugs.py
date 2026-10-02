from django.db import migrations
from django.utils.text import slugify

from conduit.apps.core.utils import generate_random_string


def backfill_empty_slugs(apps, schema_editor):
    """Articles saved before the slug signal was wired up have slug=''."""
    Article = apps.get_model("articles", "Article")

    for article in Article.objects.filter(slug=""):
        base = slugify(article.title)[:240] or "article"
        article.slug = f"{base}-{generate_random_string()}"
        article.save(update_fields=["slug"])


class Migration(migrations.Migration):
    dependencies = [
        ("articles", "0004_alter_article_id_alter_comment_id_alter_tag_id"),
    ]

    operations = [
        migrations.RunPython(backfill_empty_slugs, migrations.RunPython.noop),
    ]
