from pydantic import BaseModel, Field


class Article(BaseModel):
    title: str
    link: str
    published: str = Field(default="No Date")
