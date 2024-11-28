import random
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
import requests
import html2text
import os
from tqdm import tqdm
import time
import logging
from datetime import datetime
from pydantic import BaseModel
from typing import List, Optional, Dict
import json

# Configure logging
log_directory = "logs"
if not os.path.exists(log_directory):
    os.makedirs(log_directory)

log_filename = os.path.join(log_directory, f"freshrss_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

# Configure logging format and level
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_filename),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Set your OpenAI API key
# os.environ['OPENAI_API_KEY'] = 'your_openai_api_key'  # Replace with your API key

# FreshRSS credentials
USERNAME = 'dylan'  # Replace with your FreshRSS username
PASSWORD = 'fUULayh7T6c*9z'  # Replace with your FreshRSS password
BASE_URL = 'http://localhost/api/greader.php'  # Replace with your FreshRSS API URL

# Parameters
TIMEFRAME_HOURS = 50  # Number of past hours to fetch articles from
EXCLUDE_CATEGORIES = ['YouTube']  # Categories to exclude

class RSSContent(BaseModel):
    content: Optional[str]

class RSSAlternate(BaseModel):
    href: str

class RSSItem(BaseModel):
    id: str
    title: str
    summary: Optional[RSSContent]
    alternate: List[RSSAlternate]
    categories: List[str]
    published: int
    origin: Dict[str, str]

def get_auth_token(username, password, base_url):
    logger.info("Attempting to get auth token")
    login_url = f"{base_url}/accounts/ClientLogin"
    payload = {'Email': username, 'Passwd': password}
    try:
        response = requests.post(login_url, data=payload)
        if response.status_code == 200:
            lines = response.text.split('\n')
            for line in lines:
                if line.startswith('Auth='):
                    logger.info("Successfully obtained auth token")
                    return line.replace('Auth=', '').strip()
        logger.error(f"Failed to get auth token. Status code: {response.status_code}")
    except Exception as e:
        logger.error(f"Exception while getting auth token: {str(e)}")
    return None

def fetch_articles(auth_token, base_url, timeframe_hours=50):
    logger.info(f"Fetching articles from the past {timeframe_hours} hours")
    headers = {'Authorization': f'GoogleLogin auth={auth_token}'}
    current_timestamp = int(time.time())
    timeframe_seconds = timeframe_hours * 3600
    timestamp_n_hours_ago = current_timestamp - timeframe_seconds
    timestamp_microseconds = timestamp_n_hours_ago * 1_000_000
    
    articles_url = f"{base_url}/reader/api/0/stream/contents/user/-/state/com.google/reading-list"
    params = {
        'output': 'json',
        'n': 1000,
        'nt': timestamp_microseconds
    }
    
    try:
        response = requests.get(articles_url, headers=headers, params=params)
        if response.status_code == 200:
            data = response.json()
            articles = data.get('items', [])
            logger.info(f"Successfully fetched {len(articles)} articles")
            return articles
        logger.error(f"Failed to fetch articles. Status code: {response.status_code}")
    except Exception as e:
        logger.error(f"Exception while fetching articles: {str(e)}")
    return []

def process_articles(articles, exclude_categories=['YouTube']):
    logger.info(f"Processing {len(articles)} articles, excluding categories: {exclude_categories}")
    processed_articles = []
    h = html2text.HTML2Text()
    h.ignore_links = False
    h.bypass_tables = False
    
    for article_data in tqdm(articles, desc="Processing articles"):
        try:
            article = RSSItem(**article_data)
            if any(any(excl_cat in cat for cat in article.categories) for excl_cat in exclude_categories):
                continue

            title = article.title
            url = article.alternate[0].href if article.alternate else 'No URL'
            content_html = article.summary.content if article.summary else ''
            content_markdown = h.handle(content_html)
            full_content = f"**Title**: {title}\n**URL**: {url}\n\n{content_markdown}"
            processed_articles.append(full_content)
        except Exception as e:
            logger.error(f"Error processing article '{article_data.get('title', 'Unknown')}': {str(e)}")
            continue
    
    logger.info(f"Successfully processed {len(processed_articles)} articles")
    return processed_articles

def build_and_save_index(processed_articles):
    logger.info("Building and saving index")
    try:
        from llama_index.core import Document
        documents = [Document(text=article) for article in processed_articles]
        
        logger.info("Creating vector store index")
        index = VectorStoreIndex.from_documents(documents)
        
        logger.info("Saving index to disk")
        index.storage_context.persist(persist_dir="freshrss_index")
        
        logger.info("Index successfully built and saved")
        return index
    except Exception as e:
        logger.error(f"Error building/saving index: {str(e)}")
        raise

def load_and_query_index():
    logger.info("Loading index from disk")
    try:
        from llama_index.core import StorageContext, load_index_from_storage
        storage_context = StorageContext.from_defaults(persist_dir="freshrss_index")
        index = load_index_from_storage(storage_context)
        query_engine = index.as_query_engine()
        
        logger.info("Starting interactive query session")
        while True:
            query = input("\nEnter your question: ")
            if query.lower() == 'exit':
                logger.info("Ending query session")
                break
            
            try:
                logger.info(f"Processing query: {query}")
                response = query_engine.query(query)
                print(f"\nResponse: {response}\n")
                logger.info("Query processed successfully")
            except Exception as e:
                logger.error(f"Error processing query '{query}': {str(e)}")
    except Exception as e:
        logger.error(f"Error loading index: {str(e)}")
        raise

def debug_rss_items(auth_token, base_url, num_items=5):
    """
    Debug function to inspect the raw RSS items and their fields.
    Prints detailed information about a sample of items.
    
    Args:
        auth_token: Authentication token for FreshRSS
        base_url: Base URL for the FreshRSS API
        num_items: Number of items to inspect (default: 5)
    """
    logger.info(f"Debugging {num_items} RSS items")
    headers = {'Authorization': f'GoogleLogin auth={auth_token}'}
    
    articles_url = f"{base_url}/reader/api/0/stream/contents/user/-/state/com.google/reading-list"
    params = {
        'output': 'json',
        'n': num_items
    }
    
    try:
        response = requests.get(articles_url, headers=headers, params=params)
        if response.status_code == 200:
            data = response.json()
            items = data.get('items', [])
            
            print("\n=== RSS Feed Structure Debug ===")
            
            # First, let's see all available top-level keys in the response
            print("\nTop level response keys:")
            print(list(data.keys()))
            
            for idx, item in enumerate(items, 1):
                print(f"\n--- Item {idx} Structure ---")
                # Use Pydantic model to parse the item
                try:
                    rss_item = RSSItem(**item)
                    # Use json.dumps for pretty-printing
                    print(json.dumps(rss_item.dict(), indent=4))
                except Exception as e:
                    logger.error(f"Error parsing item {idx}: {str(e)}")
                
                print("\n" + "="*50)
            
            return items
            
        logger.error(f"Failed to fetch articles. Status code: {response.status_code}")
    except Exception as e:
        logger.error(f"Exception while debugging RSS items: {str(e)}")
    return None

def main():
    logger.info("Starting FreshRSS article indexing process")
    try:
        # Get Auth Token
        auth_token = get_auth_token(USERNAME, PASSWORD, BASE_URL)
        if not auth_token:
            logger.error("Failed to obtain auth token. Exiting.")
            return

        # Debug RSS items
        debug_items = debug_rss_items(auth_token, BASE_URL, num_items=15)
        # Stop here for debugging
        return

        # Step 1: Fetch Articles
        articles = fetch_articles(auth_token, BASE_URL, TIMEFRAME_HOURS)
        if not articles:
            logger.error("No articles fetched. Exiting.")
            return

        # Step 2: Process Articles
        processed_articles = process_articles(articles, EXCLUDE_CATEGORIES)
        if not processed_articles:
            logger.error("No articles to index after processing. Exiting.")
            return

        logger.info(f"Processing {len(processed_articles)} articles...")
        
        # Step 3: Build and save the index
        index = build_and_save_index(processed_articles)
        logger.info("Index built and saved successfully")
        
        # Step 4: Start interactive query session
        load_and_query_index()
        
    except Exception as e:
        logger.error(f"Unexpected error in main: {str(e)}")
    finally:
        logger.info("FreshRSS article indexing process completed")

if __name__ == '__main__':
    main()

