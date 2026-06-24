import ActivityAutoLoad from "./activity_auto_load"
import AnchoredPopover from "./anchored_popover"
import BrowseAutoApplyFilter from "./browse_auto_apply_filter"
import BrowseRangeControl from "./browse_range_control"
import BrowseSectionRow from "./browse_section_row"
import BrowseTagPicker from "./browse_tag_picker"
import ClientTagFilter from "./client_tag_filter"
import CommentContent from "./comment_content"
import CommentThread from "./comment_thread"
import CoverTooltip from "./cover_tooltip"
import Dialog from "./dialog"
import DraftClear from "./draft_clear"
import FadeReadPreference from "./fade_read_preference"
import FavoritesDnd from "./favorites_dnd"
import FollowAutoLoad from "./follow_auto_load"
import HomeActivityTopUp from "./home_activity_top_up"
import HomeGreeting from "./home_greeting"
import ImageCropper from "./image_cropper"
import LibraryPrefs from "./library_prefs"
import LikeButton from "./like_button"
import ListLayoutIsland from "./list_layout_island"
import LvNavGetForm from "./lv_nav_get_form"
import MobileRecommendationVote from "./mobile_recommendation_vote"
import MobileSearchHistory from "./mobile_search_history"
import ModalDialog from "./modal_dialog"
import NotFoundButton from "./not_found_button"
import NotificationsReadTracker from "./notifications_read_tracker"
import PaginationScroll from "./pagination_scroll"
import RatingStars from "./rating_stars"
import ReadMore from "./read_more"
import RelationSearch from "./relation_search"
import ReleaseFilters from "./release_filters"
import RemovalReasonForm from "./removal_reason_form"
import MarkdownEditor from "./markdown_editor"
import ReportForm from "./report_form"
import ResendCountdown from "./resend_countdown"
import SimilarVnMobileReveal from "./similar_vn_mobile_reveal"
import SpoilerScope from "./spoiler_scope"
import StatusSegments from "./status_segments"
import TagVotesAutoLoad from "./tag_votes_auto_load"
import ToastRoot from "./toast_root"
import UnsavedChanges from "./unsaved_changes"
import VNSearch from "./vn_search"
import VndbImportUploader from "./vndb_import_uploader"

export default {
  ActivityAutoLoad,
  AnchoredPopover,
  BrowseAutoApplyFilter,
  BrowseRangeControl,
  BrowseSectionRow,
  BrowseTagPicker,
  ClientTagFilter,
  CommentContent,
  CommentThread,
  CoverTooltip,
  Dialog,
  DraftClear,
  FadeReadPreference,
  FavoritesDnd,
  FollowAutoLoad,
  HomeActivityTopUp,
  HomeGreeting,
  ImageCropper,
  LibraryPrefs,
  LikeButton,
  ListLayoutIsland,
  LvNavGetForm,
  MobileRecommendationVote,
  MobileSearchHistory,
  ModalDialog,
  NotFoundButton,
  NotificationsReadTracker,
  PaginationScroll,
  RatingStars,
  ReadMore,
  RelationSearch,
  ReleaseFilters,
  RemovalReasonForm,
  MarkdownEditor,
  // Legacy alias — `<.reply_input>` still wires `phx-hook="ReplyInput"`
  // through the SaladUI/`<.markdown_editor>` extraction transition.
  ReplyInput: MarkdownEditor,
  ReportForm,
  ResendCountdown,
  SimilarVnMobileReveal,
  SpoilerScope,
  StatusSegments,
  TagVotesAutoLoad,
  ToastRoot,
  UnsavedChanges,
  VNSearch,
  VndbImportUploader
}
